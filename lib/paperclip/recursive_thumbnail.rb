module Paperclip
  class RecursiveThumbnail < Thumbnail
    def initialize file, options = {}, attachment = nil

      # если по каким-то причинам не сформировался файл
      # для прыдущего размера не кидаем ексепшен и
      # генерим файл из оригинального
      f = attachment.to_file(options[:thumbnail] || :original) rescue file
      super f, options, attachment
    end
  end
end
