# frozen_string_literal: true

module Paperclip
  class RecursiveThumbnail < Thumbnail
    def initialize(file, options = {}, attachment = nil)
      source_style = options[:thumbnail] || :original
      # если по каким-то причинам не сформировался файл прыдущего размера - генерим из оригинального
      source_file = begin
                      attachment.to_file(source_style)
                    rescue
                      Paperclip.log "Using original for #{options}"
                      file
                    end
      super(source_file, options, attachment)
    ensure
      if source_file != file && source_file.respond_to?(:close!) && !attachment&.queued_for_write&.value?(source_file)
        source_file.close!
      end
    end
  end
end
