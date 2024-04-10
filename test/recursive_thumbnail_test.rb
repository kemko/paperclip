# frozen_string_literal: true

require 'test_helper'

class RecursiveThumbnailTest < Test::Unit::TestCase
  setup do
    Paperclip::Geometry.stubs from_file: Paperclip::Geometry.parse('1x1')
    @original_file = stub("originalfile", path: 'originalfile.txt')
    @attachment = attachment({})
  end

  should "use original when style not present" do
    processor = Paperclip::RecursiveThumbnail.new(@original_file, { thumbnail: :missing, geometry: '1x1'}, @attachment)
    assert_equal @original_file, processor.file
  end

  should "use original when style failed to download" do
    @attachment.expects(:to_file).with(:missing).raises("cannot haz filez")
    processor = Paperclip::RecursiveThumbnail.new(@original_file, { thumbnail: :missing, geometry: '1x1'}, @attachment)
    assert_equal @original_file, processor.file
  end

  should "use style when present" do
    style_file = stub("stylefile", path: 'style.txt')
    style_file.expects(:close!).once
    @original_file.expects(:close!).never
    @attachment.expects(:to_file).with(:existent).returns(style_file)
    processor = Paperclip::RecursiveThumbnail.new(@original_file, { thumbnail: :existent, geometry: '1x1'}, @attachment)
    Paperclip.stubs run: ""
    assert_equal style_file, processor.file
    res = processor.make
    assert_equal Tempfile, res.class
  end
end
