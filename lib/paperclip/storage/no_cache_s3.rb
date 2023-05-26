# frozen_string_literal: true

module Paperclip
  module Storage
    # Saves file to main store, and run jobs to copy files to one or more permanent stores.
    # All stores are Fog::Storage::Directory instances (it has S3 and filesystem adapters).
    #
    # Options:
    # - `:stores` - one or more permanent storages (hash of settings for AWS resources),
    #   first one is main others are mirrors,
    # - `:key` - identifier template.
    # - `:url` - path template(?).
    #
    # It uses `#{attachement_name}_synced_to_#{store_id}` field to mark that file
    # is uploaded to particular storage.
    module NoCacheS3
      class << self
        def included(base)
          base.extend(ClassMethods)
        end
      end

      module ClassMethods
        attr_reader :key_template,
                    :url_template,
                    :stores,
                    :store_ids,
                    :main_store_id,
                    :download_by_url,
                    :upload_options

        def setup(*)
          super

          @key_template = options.fetch(:key)
          @key_template = key_template[1..-1] if key_template.start_with?('/') # rubocop:disable Style/SlicingWithRange
          @stores = options.fetch(:stores).each_with_object({}) do |(store_id, config), stores|
            stores[store_id.to_sym] = ::Aws::S3::Resource.new(client: ::Aws::S3::Client.new(
              config.slice(:access_key_id, :secret_access_key, :endpoint, :region, :force_path_style)
            )).bucket(config[:bucket])
          end
          @store_ids = options[:stores].keys.map(&:to_sym)
          @main_store_id = store_ids.first
          @url_template = options.fetch(:url)
            .gsub(':key', key_template)
            .gsub(':bucket_url', store_by(main_store_id).url)
          @download_by_url = options[:download_by_url]
          @upload_options = options[:upload_options] || {}
        end

        def store_by(store_id)
          stores.fetch(store_id.to_sym)
        end

        def synced_field_names
          @synced_field_names ||= store_ids.each_with_object({}) do |key, result|
            result[key] = :"#{attachment_name}_synced_to_#{key}"
          end
        end

        def synced_field_name(store_id)
          synced_field_names[store_id.to_sym]
        end
      end

      def initialize(*)
        super
        @queued_jobs = []
      end

      def key(style = default_style)
        return if original_filename.nil?

        interpolate(self.class.key_template, style)
      end

      def storage_url(style = default_style)
        if self.class.url_template.present?
          interpolate(self.class.url_template, style)
        else
          "#{self.class.store_by(self.class.main_store_id).url}/#{key(style)}"
        end
      end

      def reprocess!
        super
        flush_jobs
      end

      # If store_id is given, it forces download from specific store using
      # Otherway uses url to download file
      # via HTTP. This is the most compatible way to delayeds3.
      def to_file(style = default_style, store_id = nil)
        style_key = key(style)
        return download_from_store(store_id, style_key) if store_id

        result = super(style)
        return result if result

        # Download by URL only if file is synced to main store. Similar to delayeds3.
        return unless synced_to?(self.class.main_store_id)

        if self.class.download_by_url
          create_tempfile(URI.parse(presigned_url(style)).open.read)
        else
          download_from_store(self.class.main_store_id, style_key)
        end
      end

      def path(style = default_style)
        storage_url(style)
      end

      # Checks if attached file exists. When store_id is not given
      # it uses fast check and does not perform API request for synced files
      def exists?(style = default_style, store_id = nil)
        return true if !store_id && synced_to?(self.class.main_store_id)

        !self.class.store_by(store_id).object(key(style)).exists?
      end

      def assign(uploaded_file)
        super(uploaded_file)

        # если не надо ничего переписывать, ничего не трогаем
        return if !queued_for_write && !queued_for_delete

        self.class.synced_field_names.each_value do |field_name|
          next unless instance.respond_to?(field_name)

          instance.public_send("#{field_name}=", false)
        end
      end

      def flush_writes # :nodoc:
        return if queued_for_write.empty?
        return if instance.destroyed?
        # если есть, что записывать (queued_for_write), значит, данные устарели
        instance[self.class.synced_field_name(self.class.main_store_id)] = false
        sync_to(self.class.main_store_id, queued_for_write)
        unless delay_processing? && dirty?
          (self.class.store_ids - [self.class.main_store_id]).each { |store_id| enqueue_sync_job(store_id) }
        end
        # HACK: Iostream пишет в tempfile, и он нигде не закрывается. Будем закрывать хотя бы тут
        if queued_for_write[:original]&.is_a?(Tempfile)
          queued_for_write[:original].close
          queued_for_write[:original].unlink
        end
        queued_for_write.clear
      end

      def delete_styles_later(styles)
        # пока ничего не удаляем, потому что используем только для импортов, там названия файлов меняться не будут,
        #   значит, и чистить нечего
      end

      # Enqueues all pending jobs. First, jobs are placed to internal queue in flush_writes
      # (in after_save) and this method pushes them for execution (in after_commit).
      def flush_jobs
        queued_jobs&.each(&:call)&.clear
      end

      def upload_to(store_id)
        sync_to(store_id)
      end

      # Writes files from main store to other permanent stores.
      def sync_to(store_id, files = nil)
        synced_field_name = self.class.synced_field_name(store_id)
        return unless instance.respond_to?(synced_field_name)
        return true if instance.public_send(synced_field_name)

        styles_to_upload = subject_to_post_process? ? self.class.all_styles : [:original]
        files ||= styles_to_upload.each_with_object({}) do |style, result|
          file = to_file(style, self.class.main_store_id)
          # For easier monitoring
          unless file
            raise "Missing files in #{self.class.main_store_id} for #{instance.class.name}:#{instance.id}:#{style}"
          end
          result[style] = file
        end
        write_to_store(store_id, files)
        # ignore deleted objects and skip callbacks
        return if instance.class.unscoped.where(id: instance.id).update_all(synced_field_name => true) != 1

        instance.updated_at = Time.current if instance.respond_to?(:updated_at=)
        instance[synced_field_name] = true
      end

      private

      # К ссылке, сформированной по паттерну (например, через наш CDN), добавляем параметры с подписью
      def presigned_url(style)
        uri = Addressable::URI.parse(storage_url(style))
        uri.host = uri.normalized_host # punycode домена
        basic_params = uri.query_values || {}
        presign_params = Addressable::URI.parse(
          self.class.store_by(self.class.main_store_id).object(key(style)).presigned_url(:get)
        ).query_values

        result_params = basic_params.merge(presign_params)
        uri.query_values = result_params # тут addressable сам заэскейпит параметры
        uri.path = Addressable::URI.escape(uri.path)
        uri.to_s
      end

      def synced_to?(store_id)
        instance.try(self.class.synced_field_name(store_id))
      end

      attr_reader :queued_jobs

      def enqueue_sync_job(store_id)
        synced_field_name = self.class.synced_field_name(store_id)
        return unless instance.respond_to?(synced_field_name)
        instance.update_column(synced_field_name, false) if instance[synced_field_name]
        queued_jobs.push -> { DelayedUpload.upload_later(self, store_id) }
      end

      def download_from_store(store_id, key)
        object = self.class.store_by(store_id).object(key)
        return unless object.exists?

        body = object.get&.body&.read
        create_tempfile(body) if body
      end

      def write_to_store(store_id, files)
        store = self.class.store_by(store_id)
        common_options = {
          content_type: instance_read(:content_type),
          cache_control: "max-age=#{10.years.to_i}",
          acl: 'public-read'
        }.merge(self.class.upload_options)

        files.each do |style, file|
          path = key(style)
          file.rewind
          log "Saving to #{store_id}:#{path}"
          store.put_object(common_options.merge(key: path, body: file))
        end
      end
    end
  end
end
