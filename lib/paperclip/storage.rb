module Paperclip
  module Storage
    autoload :Filesystem, 'paperclip/storage/filesystem'
    autoload :Delayeds3, 'paperclip/storage/delayeds3'
    autoload :S3, 'paperclip/storage/s3'
  end
end
