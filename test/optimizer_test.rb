# frozen_string_literal: true

require 'test_helper'

class OptimizerTest < Test::Unit::TestCase
  setup do
    @pixel_jpg = Base64.decode64(
      "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP#{'/'*86}wgALCAABAAEBAREA/8QAFBAB#{'A'*21}P/aAAgBAQABPxA"
    )
    @pixel_png = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg"
    )
    @pixel_gif = Base64.decode64("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")
  end

  def with_tempfile(name, content)
    Tempfile.create([File.basename(name), File.extname(name)]) do |tempfile|
      tempfile.binmode
      tempfile.write(content)
      tempfile.flush
      tempfile.rewind
      yield tempfile
    end
  end

  context "Paperclip::Optimizer" do
    context "#real_content_type" do
      should "detect jpeg" do
        with_tempfile('pixel.jpg', @pixel_jpg) do |tempfile|
          assert_equal("image/jpeg", Paperclip::Optimizer.new(tempfile, {}).real_content_type)
        end
      end

      should("detect png") do
        with_tempfile('image.svg.png', @pixel_png) do |tempfile|
          assert_equal("image/png", Paperclip::Optimizer.new(tempfile, {}).real_content_type)
        end
      end

      should("detect gif") do
        with_tempfile('Spiked.gif', @pixel_gif) do |tempfile|
          assert_equal("image/gif", Paperclip::Optimizer.new(tempfile, {}).real_content_type)
        end
      end
    end

    context "#make" do
      should "process jpeg" do
        with_tempfile('pixel.jpg', @pixel_jpg) do |tempfile|
          res = Paperclip::Optimizer.new(tempfile, {}).make
          assert_equal("image/jpeg", Paperclip::Upfile.content_type_from_file(res.path))
        end
      end

      should("process png") do
        with_tempfile('image.svg.png', @pixel_png) do |tempfile|
          res = Paperclip::Optimizer.new(tempfile, {}).make
          assert_equal("image/png", Paperclip::Upfile.content_type_from_file(res.path))
        end
      end

      should("process gif") do
        with_tempfile('Spiked.gif', @pixel_gif) do |tempfile|
          res = Paperclip::Optimizer.new(tempfile, {}).make
          assert_equal("image/gif", Paperclip::Upfile.content_type_from_file(res.path))
        end
      end

      should("pass others") do
        invalid_content = "invalid gif"
        with_tempfile('Spiked.gif', invalid_content) do |tempfile|
          res = Paperclip::Optimizer.new(tempfile, {}).make
          assert_equal(tempfile, res)
          assert_equal(invalid_content, res.read)
        end
      end

      should("handle errors") do
        invalid_content = "invalid gif"
        with_tempfile('Spiked.gif', invalid_content) do |tempfile|
          processor = Paperclip::Optimizer.new(tempfile, {})
          processor.stubs(real_content_type: 'image/gif')
          Open3.stubs(:capture3).raises("lala")
          Paperclip.expects(:log).with { _1.include?("lala") }
          res = processor.make
          assert_equal(tempfile, res)
          assert_equal(invalid_content, res.read)
        end
      end
    end
  end
end
