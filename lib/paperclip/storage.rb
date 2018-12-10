module Paperclip
  module Storage
    autoload :Filesystem, 'paperclip/storage/filesystem'
    autoload :Delayeds3, 'paperclip/storage/delayeds3'
    autoload :Cached, 'paperclip/storage/cached'
  end
end
