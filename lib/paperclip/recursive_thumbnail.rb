# frozen_string_literal: true

module Paperclip
  class RecursiveThumbnail < Thumbnail
    def initialize(file, options = {}, attachment = nil)
      source_style = options[:thumbnail] || :original
      # если по каким-то причинам не сформировался файл прыдущего размера - генерим из оригинального
      source_file = begin
        attachment.to_file(source_style)
      rescue StandardError
        nil
      end

      unless source_file
        Paperclip.log "Using original for #{options}"
        source_file = file
      end

      @original_file = file
      super(source_file, options, attachment)
    end

    def make
      super
    ensure
      if @file != @original_file && @file.respond_to?(:close!) && !attachment&.queued_for_write&.value?(@file)
        @file.close!
      end
    end
  end
end
