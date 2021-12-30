# frozen_string_literal: true

require 'test_helper'

class PaperclipTest < Test::Unit::TestCase
  [:image_magick_path, :convert_path].each do |path|
    context "Calling Paperclip.run with an #{path} specified" do
      setup do
        Paperclip.options[:image_magick_path] = nil
        Paperclip.options[:convert_path] = nil
        Paperclip.options[path] = "/usr/bin"
        @file_path = File.join(File.dirname(__FILE__), "fixtures", "5k.png")
        @file_path2 = File.join(File.dirname(__FILE__), "fixtures", "50x50.png")
      end

      should "execute the right command" do
        Paperclip.expects(:path_for_command).with("convert").returns("/usr/bin/convert")
        Paperclip.expects(:bit_bucket).returns("/dev/null")
        Paperclip.expects(:"`").with("timeout 30 /usr/bin/convert #{@file_path} #{@file_path2} 2>/dev/null")
        Paperclip.run("convert", "#{@file_path} #{@file_path2}")
      end
    end
  end

  context "Calling Paperclip.run with no path specified" do
    setup do
      Paperclip.options[:image_magick_path] = nil
      Paperclip.options[:convert_path] = nil
      @file_path = File.join(File.dirname(__FILE__), "fixtures", "5k.png")
      @file_path2 = File.join(File.dirname(__FILE__), "fixtures", "50x50.png")
    end

    should "execute the right command" do
      Paperclip.expects(:path_for_command).with("convert").returns("convert")
      Paperclip.expects(:bit_bucket).returns("/dev/null")
      Paperclip.expects(:"`").with("timeout 30 convert #{@file_path} #{@file_path2} 2>/dev/null")
      Paperclip.run("convert", "#{@file_path} #{@file_path2}")
    end

    should "log the command when :log_command is set" do
      Paperclip.options[:log_command] = true
      Paperclip.expects(:bit_bucket).returns("/dev/null")
      Paperclip.expects(:log).with("convert #{@file_path} #{@file_path2} 2>/dev/null")
      Paperclip.expects(:"`").with("timeout 30 convert #{@file_path} #{@file_path2} 2>/dev/null")
      Paperclip.run("convert", "#{@file_path} #{@file_path2}")
    end
  end

  should "raise when sent #processor and the name of a class that exists but isn't a subclass of Processor" do
    assert_raises(Paperclip::PaperclipError){ Paperclip.processor(:attachment) }
  end

  should "raise when sent #processor and the name of a class that doesn't exist" do
    assert_raises(NameError){ Paperclip.processor(:boogey_man) }
  end

  should "return a class when sent #processor and the name of a class under Paperclip" do
    assert_equal ::Paperclip::Thumbnail, Paperclip.processor(:thumbnail)
  end

  should "call a proc sent to check_guard" do
    @dummy = Dummy.new
    @dummy.expects(:one).returns(:one)
    assert_equal :one, @dummy.avatar.send(:check_guard, lambda{|x| x.one })
  end

  should "call a method name sent to check_guard" do
    @dummy = Dummy.new
    @dummy.expects(:one).returns(:one)
    assert_equal :one, @dummy.avatar.send(:check_guard, :one)
  end

  context "Paperclip.bit_bucket" do
    context "on systems without /dev/null" do
      setup do
        File.expects(:exist?).with("/dev/null").returns(false)
      end

      should "return 'NUL'" do
        assert_equal "NUL", Paperclip.bit_bucket
      end
    end

    context "on systems with /dev/null" do
      setup do
        File.expects(:exist?).with("/dev/null").returns(true)
      end

      should "return '/dev/null'" do
        assert_equal "/dev/null", Paperclip.bit_bucket
      end
    end
  end

  context "An ActiveRecord model with an 'avatar' attachment" do
    setup do
      rebuild_model :path => "tmp/:class/omg/:style.:extension"
      @file = File.new(File.join(FIXTURES_DIR, "5k.png"), 'rb')
    end

    teardown { @file.close }

    should "not error when trying to also create a 'blah' attachment" do
      assert_nothing_raised do
        Dummy.class_eval do
          has_attached_file :blah
        end
      end
    end

    context "a validation with an if guard clause" do
      setup do
        Dummy.send(:"validates_attachment_presence", :avatar, :if => lambda{|i| i.foo })
        @dummy = Dummy.new
      end

      should "attempt validation if the guard returns true" do
        @dummy.expects(:foo).returns(true)
        @dummy.avatar.expects(:validate_presence).returns(nil)
        @dummy.valid?
      end

      should "not attempt validation if the guard returns false" do
        @dummy.expects(:foo).returns(false)
        @dummy.avatar.expects(:validate_presence).never
        @dummy.valid?
      end
    end

    context "a validation with an unless guard clause" do
      setup do
        Dummy.send(:"validates_attachment_presence", :avatar, :unless => lambda{|i| i.foo })
        @dummy = Dummy.new
      end

      should "attempt validation if the guard returns true" do
        @dummy.expects(:foo).returns(false)
        @dummy.avatar.expects(:validate_presence).returns(nil)
        @dummy.valid?
      end

      should "not attempt validation if the guard returns false" do
        @dummy.expects(:foo).returns(true)
        @dummy.avatar.expects(:validate_presence).never
        @dummy.valid?
      end
    end

    def self.should_validate validation, options, valid_file, invalid_file
      context "with #{validation} validation and #{options.inspect} options" do
        setup do
          Dummy.send(:"validates_attachment_#{validation}", :avatar, options)
          @dummy = Dummy.new
        end
        context "and assigning nil" do
          setup do
            @dummy.avatar = nil
            @dummy.valid?
          end
          if validation == :presence
            should "have an error on the attachment" do
              assert @dummy.errors[:avatar]
            end
          else
            should "not have an error on the attachment" do
              assert_equal [], @dummy.errors[:avatar]
            end
          end
        end
        context "and assigned a valid file" do
          setup do
            @dummy.avatar = valid_file
            @dummy.valid?
          end
          should "not have an error when assigned a valid file" do
            assert ! @dummy.avatar.errors.key?(validation)
          end
          should "not have an error on the attachment" do
            assert_equal [], @dummy.errors[:avatar]
          end
        end
        context "and assigned an invalid file" do
          setup do
            @dummy.avatar = invalid_file
            @dummy.valid?
          end
          should "have an error when assigned a valid file" do
            assert_not_nil @dummy.avatar.errors[validation]
          end
          should "have an error on the attachment" do
            assert @dummy.errors[:avatar]
          end
        end
      end
    end

    [[:presence,      {},                              "5k.png",   nil],
     [:size,          {:in => 1..10240},               nil,        "12k.png"],
     [:size,          {:less_than => 10240},           "5k.png",   "12k.png"],
     [:size,          {:greater_than => 8096},         "12k.png",  "5k.png"],
     [:content_type,  {:content_type => "image/png"},  "5k.png",   "text.txt"],
     [:content_type,  {:content_type => "text/plain"}, "text.txt", "5k.png"],
     [:content_type,  {:content_type => %r{image/.*}}, "5k.png",   "text.txt"]].each do |args|
      validation, options, valid_file, invalid_file = args
      valid_file   &&= File.open(File.join(FIXTURES_DIR, valid_file), "rb")
      invalid_file &&= File.open(File.join(FIXTURES_DIR, invalid_file), "rb")

      should_validate validation, options, valid_file, invalid_file
    end
  end
end
