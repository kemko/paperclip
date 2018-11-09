module Paperclip
  module Storage
    # Need to create boolean field synced_to_s3
    module Delayeds3
      # require 'aws-sdk'
      module ClassMethods
        def parse_credentials creds
          return @parsed_credentials if @parsed_credentials
          creds = find_credentials(creds).stringify_keys
          @parsed_credentials ||= (creds[Rails.env] || creds).symbolize_keys
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

      class WriteToS3Job < Struct.new(:class_name, :name, :id)
        def perform
          WriteToS3Worker.new.perform(class_name, name, id)
        end
      end

      class UploadWorker
        include ::Sidekiq::Worker
        sidekiq_options queue: :paperclip

        def perform(class_name, name, id)
          file = class_name.constantize.find_by_id(id)
          return unless file
          attachment = file.send(name)
          write(attachment)
          attachment.delete_local_files!
        rescue Errno::ESTALE
          raise if attachment && file.class.exists?(file)
        rescue Errno::ENOENT => e
          raise if attachment && file.class.exists?(file)
          Rollbar.warn(e, file_name: extract_file_name_from_error(e))
        end

        def extract_file_name_from_error(err)
          err.message.split(' - ')[-1]
        end
      end

      class WriteToS3Worker < UploadWorker
        def write(attachment)
          attachment.write_to_s3
        end
      end

      class WriteToFogWorker < UploadWorker
        def write(attachment)
          attachment.write_to_fog
        rescue Excon::Errors::SocketError => e
          raise e.socket_error if e.socket_error.is_a?(Errno::ENOENT) || e.socket_error.is_a?(Errno::ESTALE)
          raise
        end
      end

      def initialize_storage
        @s3_credentials = self.class.parse_credentials(@options[:s3_credentials])
        @bucket         = @options[:bucket]         || @s3_credentials[:bucket]
        @bucket         = @bucket.call(self) if @bucket.is_a?(Proc)
        @s3_permissions = @options[:s3_permissions] || 'public-read'
        @s3_protocol    = @options[:s3_protocol]    || (@s3_permissions == 'public-read' ? 'http' : 'https')
        @s3_host_alias  = @options[:s3_host_alias]

        @fog_provider   = @options[:fog_provider]
        @fog_directory  = @options[:fog_directory]
        @fog_credentials = @options[:fog_credentials]

        @queued_jobs    = []
      end

      def url(style = default_style, include_updated_timestamp = true)
        # for delayed_paperclip
        return interpolate(@processing_url, style) if @instance.try("#{name}_processing?")
        template = instance_read(:synced_to_s3) ? options[:s3_url] : options[:filesystem_url]
        interpolate_url(template, style, include_updated_timestamp)
      end

      # Метод необходим в ассетах
      def filesystem_url(style = default_style, include_updated_timestamp = true)
        interpolate_url(options[:filesystem_url], style, include_updated_timestamp)
      end

      def path(style = default_style)
        return if original_filename.nil?
        path = instance_read(:synced_to_s3) ? options[:s3_path] : options[:filesystem_path]
        interpolate(path, style)
      end

      def filesystem_path(style = default_style)
        return if original_filename.nil?
        interpolate(options[:filesystem_path], style)
      end

      def reprocess!
        super
        flush_jobs
      end

      def aws_bucket
        return @aws_bucket if @aws_bucket

        params = { region: @s3_credentials[:region] || 'us-east-1',
                   access_key_id: @s3_credentials[:access_key_id],
                   secret_access_key: @s3_credentials[:secret_access_key] }

        params[:endpoint] = @s3_credentials[:endpoint] if @s3_credentials[:endpoint].present?
        params[:http_proxy] = @s3_credentials[:http_proxy] if @s3_credentials[:http_proxy].present?

        s3_client = Aws::S3::Client.new(params)

        s3_resource = Aws::S3::Resource.new(client: s3_client)
        @aws_bucket = s3_resource.bucket(bucket_name)
      end

      def bucket_name
        @bucket
      end

      def s3_host_alias
        @s3_host_alias
      end

      def synced_to_s3_field
        @synced_to_s3_field ||= "#{name}_synced_to_s3".freeze
      end

      def synced_to_fog_field
        @synced_to_fog_field ||= "#{name}_synced_to_fog".freeze
      end

      def to_file style = default_style
        @queued_for_write[style] || (File.new(filesystem_path(style), 'rb') if exists?(style)) || download_file(style)
      end

      def download_file(style = default_style)
        return unless instance_read(:synced_to_s3)
        temp_file = Tempfile.new(['product_image', File.extname(filesystem_path(style))], encoding: 'ascii-8bit')
        uri = URI(URI.encode(url(style)))
        Net::HTTP.start(uri.host, uri.port) do |http|
          req = Net::HTTP::Get.new uri
          http.request(req) do |response|
            if response.is_a?(Net::HTTPOK)
              response.read_body{|chunk| temp_file.write(chunk)}
            else
              return nil
            end
          end
        end
        temp_file.flush
        temp_file.rewind
        temp_file
      end

      alias_method :to_io, :to_file

      def parse_credentials creds
        creds = find_credentials(creds).stringify_keys
        (creds[Rails.env] || creds).symbolize_keys
      end

      def s3_protocol
        @s3_protocol
      end

      def exists?(style = default_style)
        File.exist?(filesystem_path(style))
      end

      def s3_path style
        interpolate(options[:s3_path], style)
      end

      def filesystem_paths
        h = {}
        [:original, *@styles.keys].uniq.map do |style|
          h[style] = filesystem_path(style) if File.exist?(filesystem_path(style))
        end
        h
      end

      def write_to_s3
        return true if instance_read(:synced_to_s3)
        paths = filesystem_paths
        if paths.length < styles.length || paths.empty? # To make monitoring easier
          raise RuntimeError.new("Local files not found for Image:#{instance_read(:id)}")
        end
        paths.each do |style, file|
          log("saving to s3 #{file}")
            s3_object = aws_bucket.object(s3_path(style).gsub(/^\/+/,''))
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

      def fog_storage
        @fog_storage ||= Fog::Storage.new(@fog_credentials.merge(provider: @fog_provider).symbolize_keys)
      end

      def write_to_fog
        return unless instance.respond_to? synced_to_fog_field
        return true if instance_read(:synced_to_fog)
        paths = filesystem_paths
        if paths.length < styles.length || paths.empty? # To make monitoring easier
          raise RuntimeError.new("Local files not found for Image:#{instance_read(:id)}")
        end
        paths.each do |style, file|
          path = s3_path(style)
          path = path[1..-1] if path.start_with?('/')
          log "Saving to Fog with key #{path}"
          options = {
            "Content-Type" => instance_read(:content_type),
            "Cache-Control" => "max-age=#{10.year.to_i}",
            "x-goog-acl" => "public-read"
          }

          File.open(file, 'r') do |f|
            fog_storage.put_object @fog_directory, path, f, options
          end
        end
        # не вызываем колбеки и спокойно себя ведем если объект удален
        if instance.class.unscoped.where(id: instance.id).update_all(synced_to_fog_field => true) == 1
          instance.touch
        end
      end


      def flush_writes #:nodoc:
        @queued_for_write.each do |style, file|
          file.close
          FileUtils.mkdir_p(File.dirname(filesystem_path(style)))
          log("saving to filesystem #{filesystem_path(style)}")
          FileUtils.mv(file.path, filesystem_path(style))
          FileUtils.chmod(0644, filesystem_path(style))
        end

        unless @queued_for_write.empty? || (delay_processing? && @was_dirty)
          instance.update_column(synced_to_s3_field, false) if instance_read(:synced_to_s3)
          if instance.respond_to?(synced_to_fog_field) && instance_read(:synced_to_fog)
            instance.update_column(synced_to_fog_field, false)
          end
          @queued_jobs.push -> {
            WriteToS3Worker.perform_async(instance.class.to_s, @name, instance.id)
            WriteToFogWorker.perform_async(instance.class.to_s, @name, instance.id)
          }
        end
        @queued_for_write = {}
      end

      # Deletes a file and all parent directories if they are empty
      def delete_recursive(path)
        initial_path = path
        begin
          FileUtils.rm(path)
        rescue Errno::ENOENT, Errno::ESTALE
          nil
        rescue Errno::EEXIST
          raise 'Image still stored locally after deletion' if File.exist?(path)
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

      def flush_deletes #:nodoc:
        # если мы картинку заливали в облака, значит мы скорее всего ее уже удалили
        # и можно не нагружать хранилище проверками
        if !instance.is_a?(AccountFile) && instance_read(:synced_to_fog) &&
           instance_read(:synced_to_s3)
           @queued_for_delete = []
           return
        end

        @queued_for_delete.each do |path|
          log("Deleting local file #{path}")
          delete_recursive(path)
        end
        @queued_for_delete = []
      end

      def delete_local_files!
        return if instance.is_a?(AccountFile)
        instance.reload
        if instance_read(:synced_to_fog) && instance_read(:synced_to_s3)
          filesystem_paths.values.each do |filename|
            log("Deleting local file #{filename}")
            delete_recursive(filename)
          end
        end
      end

      def flush_jobs
        @queued_jobs&.each(&:call)
        @queued_jobs = []
      end
    end
  end
end
