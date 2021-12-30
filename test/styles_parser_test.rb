# frozen_string_literal: true

require 'test_helper'

class StylesParserTest < Test::Unit::TestCase
  context "An attachment with :convert_options" do
    setup do
      options = {
        styles: {
          thumb: "100x100",
          large: "400x400"
        },
        convert_options: {
          all: "-do_stuff",
          thumb: "-thumbnailize"
        }
      }
      @parser = Paperclip::StylesParser.new(options)
    end

    should "report the correct options when sent #extra_options_for(:thumb)" do
      assert_equal "-thumbnailize -do_stuff", @parser.extra_options_for(:thumb), @parser.convert_options.inspect
    end

    should "report the correct options when sent #extra_options_for(:large)" do
      assert_equal "-do_stuff", @parser.extra_options_for(:large)
    end

    before_should "call extra_options_for(:thumb/:large)" do
      Paperclip::StylesParser.any_instance.expects(:extra_options_for).with(:thumb).at_least_once
      Paperclip::StylesParser.any_instance.expects(:extra_options_for).with(:large).at_least_once
    end
  end
end
