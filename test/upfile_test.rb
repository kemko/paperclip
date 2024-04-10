# frozen_string_literal: true

require 'test_helper'

class UpfileTest < Test::Unit::TestCase
  context "content_type_from_ext" do
    {
      'lala' => 'application/x-octet-stream',
      'lala.foo' => 'application/x-foo',
      '__.jpg' => "image/jpeg",
      '_.jpeg' => "image/jpeg",
      '__.tif' => "image/tiff",
      '_.tiff' => "image/tiff",

      '_.png' => "image/png",
      '_.gif' => "image/gif",
      '_.bmp' => "image/bmp",
      "_.webp" => "image/webp",

      # '_.pngfoo' => 'application/x-pngfoo', # ??
      # '_.htmfoo' => 'application/x-htmfoo', # ?

      '_.csv' => "text/csv",
      '_.xml' => "text/xml",
      '_.css' => "text/css",
      '_.js' => "text/js", # ???

      '_.html' => 'text/html',
      '__.htm' => 'text/html',

      "_.txt" => "text/plain",
      "_.liquid" => "text/x-liquid",
      '_.svg' => 'image/svg+xml',
      '_.xls' => 'application/vnd.ms-excel'
    }.each_pair do |example, result|
      should "return #{result} for #{example}" do
        assert_equal result, Paperclip::Upfile.content_type_from_ext(example)
      end
    end
  end
end
