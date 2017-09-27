module Paperclip
  module Storage

    # The default place to store attachments is in the filesystem. Files on the local
    # filesystem can be very easily served by Apache without requiring a hit to your app.
    # They also can be processed more easily after they've been saved, as they're just
    # normal files. There is one Filesystem-specific option for has_attached_file.
    # * +path+: The location of the repository of attachments on disk. This can (and, in
    #   almost all cases, should) be coordinated with the value of the +url+ option to
    #   allow files to be saved into a place where Apache can serve them without
    #   hitting your app. Defaults to
    #   ":rails_root/public/:attachment/:id/:style/:basename.:extension"
    #   By default this places the files in the app's public directory which can be served
    #   directly. If you are using capistrano for deployment, a good idea would be to
    #   make a symlink to the capistrano-created system directory from inside your app's
    #   public directory.
    #   See Paperclip::Attachment#interpolate for more information on variable interpolaton.
    #     :path => "/var/app/attachments/:class/:id/:style/:basename.:extension"
    module Filesystem
      def self.extended base
      end

      def exists?(style = default_style)
        if original_filename
          File.exist?(path(style))
        else
          false
        end
      end

      # Returns representation of the data of the file assigned to the given
      # style, in the format most representative of the current storage.
      def to_file style = default_style
        @queued_for_write[style] || (File.new(path(style), 'rb') if exists?(style))
      end
      alias_method :to_io, :to_file

      def flush_writes #:nodoc:
        @queued_for_write.each do |style, file|
          file.close
          FileUtils.mkdir_p(File.dirname(path(style)))
          log("saving #{path(style)}")
          FileUtils.mv(file.path, path(style))
          FileUtils.chmod(0644, path(style))
        end
        @queued_for_write = {}
      end

      def flush_deletes #:nodoc:
        @queued_for_delete.each do |path|
          begin
            log("deleting #{path}")
            FileUtils.rm(path)
          rescue Errno::ENOENT => e
            # ignore file-not-found, let everything else pass
          end
          begin
            while(true)
              path = File.dirname(path)
              if Dir.entries(path).empty?
                FileUtils.rmdir(path)
              else
                break
              end
            end
          rescue Errno::EEXIST, Errno::ENOTEMPTY, Errno::ENOENT, Errno::EINVAL, Errno::ENOTDIR
            # Stop trying to remove parent directories
          rescue SystemCallError => e
            log("There was an unexpected error while deleting directories: #{e.class}")
            # Ignore it
          end
        end
        @queued_for_delete = []
      end
    end

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
        @s3_options     = @options[:s3_options]     || {}
        @s3_permissions = @options[:s3_permissions] || 'public-read'
        @s3_protocol    = @options[:s3_protocol]    || (@s3_permissions == 'public-read' ? 'http' : 'https')
        @s3_headers     = @options[:s3_headers]     || {}
        @s3_host_alias  = @options[:s3_host_alias]
        @job_priority   = @options[:job_priority]

        @fog_provider   = @options[:fog_provider]
        @fog_directory  = @options[:fog_directory]
        @fog_credentials = @options[:fog_credentials]

        @s3_url         = ":s3_path_url" unless @s3_url.to_s.match(/^:s3.*url$/)
        Paperclip.interpolates(:s3_alias_url) do |attachment, style|
          ":cdn_protocol://:cdn_domain/#{attachment.path(style).gsub(%r{^/}, "")}"
        end
      end

      def aws_bucket
        return @aws_bucket if @aws_bucket

        s3_client = Aws::S3::Client.new(
          region:            @s3_credentials[:region] || 'us-east-1',
          access_key_id:     @s3_credentials[:access_key_id],
          secret_access_key: @s3_credentials[:secret_access_key]
        )

        s3_resource = Aws::S3::Resource.new(client: s3_client)
        @aws_bucket = s3_resource.bucket(bucket_name)
      end

      def bucket_name
        @bucket
      end

      def s3_host_alias
        @s3_host_alias
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
          h[style] = filesystem_path(style) if File.exists?(filesystem_path(style))
        end
        h
      end

      def write_to_s3
        return true if instance_read(:synced_to_s3)
        filesystem_paths.each do |style, file|
          log("saving to s3 #{file}")
            s3_object = aws_bucket.object(s3_path(style).gsub(/^\/+/,''))
            s3_object.upload_file(file,
                                  cache_control: "max-age=#{10.year.to_i}",
                                  content_type: instance_read(:content_type),
                                  expires: 10.year.from_now.httpdate,
                                  acl: 'public-read')
        end
        instance.update_column("#{name}_synced_to_s3", true)
      end

      def fog_storage
        @fog_storage ||= Fog::Storage.new(@fog_credentials.merge(provider: @fog_provider).symbolize_keys)
      end

      def write_to_fog
        return unless instance.respond_to? "#{name}_synced_to_fog"
        return true if instance_read(:synced_to_fog)
        paths = filesystem_paths
        raise RuntimeError.new("Local files not found for Image:#{instance_read(:id)}") if paths.length < styles.length # To make monitoring easier
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
        instance.update_column("#{name}_synced_to_fog", true)
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
          instance.update_column("#{name}_synced_to_s3", false) if instance_read(:synced_to_s3)
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
          FileUtils.rm(path) if File.exist?(path)
        rescue Errno::ENOENT, Errno::ESTALE => e
        end
        begin
          while(true)
            path = File.dirname(path)
            FileUtils.rmdir(path)
            break if File.exists?(path) # Ruby 1.9.2 does not raise if the removal failed.
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
    end
  end
end
