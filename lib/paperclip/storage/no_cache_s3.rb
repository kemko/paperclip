# frozen_string_literal: true

module Paperclip
  module Storage
    # Saves file to main store, and run jobs to copy files to one or more permanent stores.
    # All stores are Fog::Storage::Directory instances (it has S3 and filesystem adapters).
    #
    # Options:
    # - `:stores` - one or more permanent storages (hash of {id => fog_directory}),
    #   first one is main others are mirrors,
    # - `:key` - identifier template.
    # - `:url` - path template(?).
    #   Values support :key interpolation which is merformed at configuration-time.
    # - `:to_file_using_fog` - use fog interface in #to_file to fetch file from store.
    #   If disabled, downloads file by url via usual HTTP request.
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
                    :download_by_url

        def setup(*)
          super

          @key_template = options.fetch(:key)
          @key_template = key_template[1..-1] if key_template.start_with?('/') # rubocop:disable Style/SlicingWithRange
          @url_template = options.fetch(:url).gsub(':key', key_template)
          @stores = options.fetch(:stores).symbolize_keys
          @store_ids = options[:stores].keys.map(&:to_sym)
          @main_store_id = store_ids.first
          @download_by_url = options[:download_by_url]
        end

        def store_by(store_id)
          stores.fetch(store_id.to_sym)
        end

        def synced_field_name(store_id)
          @synced_field_names ||= store_ids.each_with_object({}) do |key, result|
            result[key] = :"#{attachment_name}_synced_to_#{key}"
          end
          @synced_field_names[store_id.to_sym]
        end
      end

      def initialize(*)
        super
        @queued_jobs = []
      end

      def key(style = default_style)
        interpolate(self.class.key_template, style)
      end

      def storage_url(style = default_style)
        interpolate(self.class.url_template, style)
      end

      def reprocess!
        super
        flush_jobs
      end

      # If store_id is given, it forces download from specific store using fog interface.
      # Otherway uses url to download file
      # via HTTP. This is the most compatible way to delayeds3.
      def to_file(style = default_style, store_id = nil)
        style_key = key(style)
        return download_from_fog(store_id, style_key) if store_id

        result = super(style)
        return result if result

        # Download by URL only if file is synced to main store. Similar to delayeds3.
        return unless synced_to?(self.class.main_store_id)

        if self.class.download_by_url
          # FIXME: do we need to escape here?
          uri = URI(URI::DEFAULT_PARSER.escape(storage_url(style)))
          response = Net::HTTP.get_response(uri)
          create_tempfile(response.body) if response.is_a?(Net::HTTPOK)
        else
          download_from_fog(self.class.main_store_id, style_key)
        end
      end

      def path(*)
        raise '#path is not available for this type of storage, use #to_file instead'
      end

      # Checks if attached file exists. When store_id is not given
      # it uses fast check and does not perform API request for synced files
      def exists?(style = default_style, store_id = nil)
        return true if !store_id && synced_to?(self.class.main_store_id)

        !self.class.store_by(store_id).files.head(key(style)).nil?
      end

      def flush_writes # :nodoc:
        return if queued_for_write.empty?

        write_to_store(self.class.main_store_id, queued_for_write)
        unless delay_processing? && dirty?
          (self.class.store_ids - [self.class.main_store_id]).each { |store_id| enqueue_sync_job(store_id) }
        end
        queued_for_write.clear
      end

      # Important: It does not delete files from permanent stores.
      def delete_styles_later(styles)
        # этот метод удаляет картинки из стораджа-кэша, а в данном типе стораджа у нас его нет
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
      def sync_to(store_id)
        synced_field_name = self.class.synced_field_name(store_id)
        return unless instance.respond_to?(synced_field_name)
        return true if instance.public_send(synced_field_name)

        files = self.class.all_styles.each_with_object({}) do |style, result|
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

        instance.touch
        instance[synced_field_name] = true
      end

      private

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

      def download_from_fog(store_id, key)
        body = self.class.store_by(store_id).files.get(key)&.body
        create_tempfile(body) if body
      end

      def write_to_store(store_id, files)
        store = self.class.store_by(store_id)
        common_options = {
          content_type: instance_read(:content_type),
          cache_control: "max-age=#{10.years.to_i}"
        }
        files.each do |style, file|
          path = key(style)
          log "Saving to #{store_id}:#{path}"
          store.files.create(
            key: path,
            public: true,
            body: file,
            **common_options
          )
        end
      end
    end
  end
end
