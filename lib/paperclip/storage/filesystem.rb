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
  end
end
