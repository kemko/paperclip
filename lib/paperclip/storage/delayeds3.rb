begin
  require "aws-sdk-s3"
rescue LoadError => e
  e.message << " (You may need to install the aws-sdk-s3 gem)"
  raise e
end

module Paperclip
  module Storage
    # Need to create boolean field synced_to_s3
    module Delayeds3
      class << self
        def included(base)
          base.extend(ClassMethods)
        end

        def parse_credentials creds
          creds = find_credentials(creds).stringify_keys
          (creds[Rails.env] || creds).symbolize_keys
        end

        def find_credentials creds
          case creds
          when File
            YAML.load_file(creds.path)
          when String
            YAML.load_file(creds)
          when Hash
            creds
          else
            raise ArgumentError, "Credentials are not a path, file, or hash."
          end
        end
      end

      module ClassMethods
        attr_reader :s3_url_template, :s3_path_template,
                    :filesystem_url_template, :filesystem_path_template,
                    :s3_credentials, :s3_bucket,
                    :fog_provider, :fog_credentials, :fog_directory,
                    :synced_to_s3_field, :synced_to_fog_field

        def setup(*)
          super

          @s3_url_template = options[:s3_url]
          @s3_path_template = options[:s3_path]
          @filesystem_url_template = options[:filesystem_url]
          @filesystem_path_template = options[:filesystem_path]

          @s3_credentials = Delayeds3.parse_credentials(options[:s3_credentials])
          @s3_bucket = options[:bucket] || @s3_credentials[:bucket]

          @fog_provider = options[:fog_provider]
          @fog_directory = options[:fog_directory]
          @fog_credentials = options[:fog_credentials].symbolize_keys

          @synced_to_s3_field ||= :"#{attachment_name}_synced_to_s3"
          @synced_to_fog_field ||= :"#{attachment_name}_synced_to_fog"
        end

        def fog_storage
          @fog_storage ||= Fog::Storage.new(fog_credentials.merge(provider: fog_provider))
        end

        def aws_bucket
          @aws_bucket ||= begin
            params = s3_credentials.reject { |_k, v| v.blank? }
            params[:region] ||= 'us-east-1'
            s3_client = Aws::S3::Client.new(params)
            s3_resource = Aws::S3::Resource.new(client: s3_client)
            s3_resource.bucket(s3_bucket)
          end
        end
      end

      delegate :synced_to_s3_field, :synced_to_fog_field, to: :class

      def initialize(*)
        super
        @queued_jobs = []
      end

      def storage_url(style = default_style)
        template = instance_read(:synced_to_s3) ? self.class.s3_url_template : self.class.filesystem_url_template
        interpolate(template, style)
      end

      def path(style = default_style)
        return if original_filename.nil?
        path = instance_read(:synced_to_s3) ? self.class.s3_path_template : self.class.filesystem_path_template
        interpolate(path, style)
      end

      def filesystem_path(style = default_style)
        return if original_filename.nil?
        interpolate(self.class.filesystem_path_template, style)
      end

      def reprocess!
        super
        flush_jobs
      end

      def to_file style = default_style
        super || (File.new(filesystem_path(style), 'rb') if exists?(style, :cache)) || download_file(style)
      end

      def download_file(style = default_style)
        return unless instance_read(:synced_to_s3)
        uri = URI(URI.encode(url(style)))
        response = Net::HTTP.get_response(uri)
        create_tempfile(response.body) if response.is_a?(Net::HTTPOK)
      end

      # Checks if attached file exists. When store_id is not given
      # it uses fast check and does not perform API request for synced files
      def exists?(style = default_style, store_id = nil)
        return true if !store_id && instance_read(:synced_to_s3)
        store_id ||= :cache
        case store_id
        when :cache
          File.exist?(filesystem_path(style))
        when :s3
          self.class.aws_bucket.object(s3_path(style)).exists?
        when :fog
          begin
            self.class.fog_storage.head_object(self.class.fog_directory, s3_path(style))
            true
          rescue Excon::Error::NotFound
            false
          end
        else
          raise 'Unknown store'
        end
      end

      def s3_path style
        result = interpolate(self.class.s3_path_template, style)
        result.start_with?('/') ? result[1..-1] : result
      end

      def filesystem_paths(styles = self.class.all_styles)
        h = {}
        styles.uniq.map do |style|
          path = filesystem_path(style)
          h[style] = path if File.exist?(path)
        end
        h
      end

      def write_to_s3
        return true if instance_read(:synced_to_s3)
        paths = filesystem_paths
        if paths.length < styles.length || paths.empty? # To make monitoring easier
          raise "Local files not found for #{instance.class.name}:#{instance.id}"
        end
        paths.each do |style, file|
          log("saving to s3 #{file}")
            s3_object = self.class.aws_bucket.object(s3_path(style))
            s3_object.upload_file(file,
                                  cache_control: "max-age=#{10.year.to_i}",
                                  content_type: instance_read(:content_type),
                                  expires: 10.year.from_now.httpdate,
                                  acl: 'public-read')
        end
        if instance.class.unscoped.where(id: instance.id).update_all(synced_to_s3_field => true) == 1
          instance.touch
        end
      end

      def write_to_fog
        return unless instance.respond_to? synced_to_fog_field
        return true if instance_read(:synced_to_fog)
        paths = filesystem_paths
        if paths.length < styles.length || paths.empty? # To make monitoring easier
          raise "Local files not found for #{instance.class.name}:#{instance.id}"
        end
        paths.each do |style, file|
          path = s3_path(style)
          log "Saving to Fog with key #{path}"
          options = {
            "Content-Type" => instance_read(:content_type),
            "Cache-Control" => "max-age=#{10.year.to_i}",
            "x-goog-acl" => "public-read"
          }

          File.open(file, 'r') do |f|
            self.class.fog_storage.put_object self.class.fog_directory, path, f, options
          end
        end
        # не вызываем колбеки и спокойно себя ведем если объект удален
        if instance.class.unscoped.where(id: instance.id).update_all(synced_to_fog_field => true) == 1
          instance.touch
        end
      rescue Excon::Errors::SocketError => e
        raise e.socket_error if e.socket_error.is_a?(Errno::ENOENT) || e.socket_error.is_a?(Errno::ESTALE)
        raise
      end

      def flush_writes #:nodoc:
        return if queued_for_write.empty?

        queued_for_write.each do |style, file|
          file.close
          FileUtils.mkdir_p(File.dirname(filesystem_path(style)))
          log("saving to filesystem #{filesystem_path(style)}")
          FileUtils.mv(file.path, filesystem_path(style))
          FileUtils.chmod(0644, filesystem_path(style))
        end

        unless delay_processing? && dirty?
          instance.update_column(synced_to_s3_field, false) if instance_read(:synced_to_s3)
          if instance.respond_to?(synced_to_fog_field) && instance_read(:synced_to_fog)
            instance.update_column(synced_to_fog_field, false)
          end
          queued_jobs.push -> { DelayedUpload.upload_later(self, :s3) }
          queued_jobs.push -> { DelayedUpload.upload_later(self, :fog) }
        end
        queued_for_write.clear
      end

      # Deletes a file and all parent directories if they are empty
      def delete_recursive(path)
        initial_path = path
        begin
          FileUtils.rm(path)
        rescue Errno::ENOENT, Errno::ESTALE, Errno::EEXIST
          nil
        end
        begin
          while(true)
            path = File.dirname(path)
            FileUtils.rmdir(path)
            break if File.exist?(path) # Ruby 1.9.2 does not raise if the removal failed.
          end
        rescue Errno::EEXIST, Errno::ENOTEMPTY, Errno::ENOENT, Errno::EINVAL, Errno::ENOTDIR, Errno::ESTALE => e
        rescue SystemCallError => e
          Rollbar.error(e, {path: path, initial_path: initial_path})
        end
      end

      def delete_styles_later(styles)
        # если мы картинку заливали в облака, значит мы скорее всего ее уже удалили
        # и можно не нагружать хранилище проверками
        return if instance_read(:synced_to_fog) && instance_read(:synced_to_s3)
        filenames = filesystem_paths(styles).values
        -> { delete_local_files!(filenames) }
      end

      def delete_local_files!(filenames = filesystem_paths.values)
        filesystem_paths.values.each do |filename|
          log("Deleting local file #{filename}")
          delete_recursive(filename)
        end
      end

      def flush_jobs
        queued_jobs&.each(&:call).clear
      end

      def upload_to(store_id)
        case store_id.to_s
        when 's3' then write_to_s3
        when 'fog' then write_to_fog
        else raise 'Unknown store id'
        end
        instance.reload
        delete_local_files! if instance_read(:synced_to_fog) && instance_read(:synced_to_s3)
      end

      private

      attr_reader :queued_jobs
    end
  end
end
