# frozen_string_literal: true

require 'test_helper'

class IOStreamTest < Test::Unit::TestCase
  context "A file" do
    setup do
      rebuild_model
      @file = File.new(File.join(File.dirname(__FILE__), "fixtures", "5k.png"), 'rb')
      @dummy = Dummy.new
      @dummy.avatar = @file
    end

    teardown { @file.close }

    context "that is sent #to_tempfile" do
      setup do
        assert @tempfile = @dummy.avatar.to_tempfile(@file)
      end

      should "convert it to a Tempfile" do
        assert @tempfile.is_a?(Tempfile)
      end

      should "have the Tempfile contain the same data as the file" do
        @file.rewind; @tempfile.rewind
        assert_equal @file.read, @tempfile.read
      end
    end
  end
end
