module Paperclip
  # The Upfile module is a convenience module for adding uploaded-file-type methods
  # to the +File+ class. Useful for testing.
  #   user.avatar = File.new("test/test_avatar.jpg")
  module Upfile
    # Infer the MIME-type of the file from the extension.
    def content_type
      Paperclip::Upfile.content_type_from_ext self.path
    end

    # TODO: Переписать через MIME::Types
    def self.content_type_from_ext(path)
      type = (path.match(/\.(\w+)$/)[1] rescue "octet-stream").downcase
      case type
      when %r"jpe?g"                 then "image/jpeg"
      when %r"tiff?"                 then "image/tiff"
      when %r"png", "gif", "bmp"     then "image/#{type}"
      when "txt"                     then "text/plain"
      when %r"html?"                 then "text/html"
      when "csv", "xml", "css", "js" then "text/#{type}"
      when "liquid"                  then "text/x-liquid"
      else "application/x-#{type}"
      end
    end

    def self.content_type_from_file(path)
      Paperclip
        .run("file", "--mime-type #{path.shellescape}")
        .split(/:\s+/)[1]
        .gsub("\n", "")
    end

    attr_writer :original_filename

    # Returns the file's normal name.
    def original_filename
      @original_filename ||= File.basename(path)
    end

    # Returns the size of the file.
    def size
      File.size(self)
    end
  end
end

if defined? StringIO
  class StringIO
    attr_accessor :original_filename, :content_type

    def original_filename
      @original_filename ||= "stringio.txt"
    end

    def content_type
      @content_type ||= Paperclip::Upfile.content_type_from_ext original_filename
    end
  end
end

class FastUploadFile < File
  attr_accessor :original_filename, :content_type

  def initialize(uploaded_file)
    @original_filename = uploaded_file['original_name']
    @content_type      = uploaded_file['content_type']
    super uploaded_file['filepath']
  end
end

class File #:nodoc:
  include Paperclip::Upfile
end

