module Paperclip
  module Storage
    autoload :Filesystem, 'paperclip/storage/filesystem'
    autoload :DelayedUpload, 'paperclip/storage/delayed_upload'
    autoload :Delayeds3, 'paperclip/storage/delayeds3'
    autoload :Cached, 'paperclip/storage/cached'
    autoload :NoCacheS3, 'paperclip/storage/no_cache_s3'
  end
end
