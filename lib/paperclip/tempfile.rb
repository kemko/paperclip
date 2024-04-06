# frozen_string_literal: true

require 'English'

module Paperclip
  # Due to how ImageMagick handles its image format conversion and how Tempfile
  # handles its naming scheme, it is necessary to override how Tempfile makes
  # its names so as to allow for file extensions. Idea taken from the comments
  # on this blog post:
  # http://marsorange.com/archives/of-mogrify-ruby-tempfile-dynamic-class-definitions
  class Tempfile < ::Tempfile
    # это похоже актуально только для java (не проверял, в mri 3.2 точно не вызывается)

    # Replaces Tempfile's +make_tmpname+ with one that honors file extensions.
    def make_tmpname(basename, n)
      extension = File.extname(basename)
      sprintf("%s,%d,%d%s", File.basename(basename, extension), $PROCESS_ID, n.to_i, extension)
    end
  end
end
