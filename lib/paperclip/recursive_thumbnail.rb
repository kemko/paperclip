module Paperclip
  class RecursiveThumbnail < Thumbnail
    def initialize file, options = {}, attachment = nil

      # если по каким-то причинам не сформировался файл
      # для прыдущего размера не кидаем ексепшен и
      # генерим файл из оригинального
      source_style = options[:thumbnail] || :original
      # TODO: вообще queued_for_write[source_style] место в NoCacheS3#to_file
      f = attachment&.queued_for_write&.dig(source_style)&.tap(&:rewind)
      # TODO: и надо сносить файл если все же была загрузка
      f ||= attachment.to_file(source_style) rescue file # rubocop:disable Style/RescueModifier
      super(f, options, attachment)
    end
  end
end
