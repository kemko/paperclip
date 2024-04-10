require 'test_helper'

class Dummy # rubocop:disable Lint/EmptyClass
  # This is a dummy class
end

class AttachmentTest < Test::Unit::TestCase
  ATTACHMENT_OPTIONS_TO_VARIABLES_MAPPING = {
    url: :url_template,
    path: :path_template,
    styles: :styles,
    default_url: :default_url,
    default_style: :default_style,
    whiny: :whiny
  }.freeze

  should "return the path based on the url by default" do
    @attachment = attachment :url => "/:class/:id/:basename"
    @model = @attachment.instance
    @model.id = 1234
    @model.avatar_file_name = "fake.jpg"
    assert_equal "#{Rails.root}/public/fake_models/1234/fake", @attachment.path
  end

  context "Attachment default_options" do
    setup do
      rebuild_model
      @old_default_options = Paperclip::Attachment.default_options.dup
      @new_default_options = @old_default_options.merge({
        :path => "argle/bargle",
        :url => "fooferon",
        :default_url => "not here.png"
      })
    end

    teardown do
      Paperclip::Attachment.default_options.merge! @old_default_options
    end

    should "be overrideable" do
      Paperclip::Attachment.default_options.merge!(@new_default_options)
      @new_default_options.keys.each do |key|
        assert_equal @new_default_options[key],
                     Paperclip::Attachment.default_options[key]
      end
    end

    context "without an Attachment" do
      setup do
        @dummy = Dummy.new
      end

      should "return false when asked exists?" do
        assert !@dummy.avatar.exists?
      end
    end

    context "on an Attachment" do
      setup do
        @dummy = Dummy.new
        @attachment = @dummy.avatar
      end

      ATTACHMENT_OPTIONS_TO_VARIABLES_MAPPING.each do |option, variable|
        should "be the default_options for #{option}" do
          assert_equal @old_default_options[option],
                       @attachment.class.instance_variable_get("@#{variable}")
        end
      end

      context "when redefined" do
        setup do
          rebuild_class @new_default_options
          @dummy = Dummy.new
          @attachment = @dummy.avatar
        end

        ATTACHMENT_OPTIONS_TO_VARIABLES_MAPPING.each do |option, variable|
          should "be the new default_options for #{option}" do
            assert_equal @new_default_options[option],
                         @attachment.class.instance_variable_get("@#{variable}")
          end
        end
      end
    end
  end

  context "An attachment with similarly named interpolations" do
    setup do
      rebuild_model :path => ":id.omg/:id-bbq/:id/what/:id_partition.wtf"
      @dummy = Dummy.new
      @dummy.stubs(:id).returns(1024)
      @file = File.new(File.join(File.dirname(__FILE__),
                                 "fixtures",
                                 "5k.png"), 'rb')
      @dummy.avatar = @file
    end

    teardown { @file.close }

    should "make sure that they are interpolated correctly" do
      assert_equal "1024.omg/1024-bbq/1024/what/000/001/024.wtf", @dummy.avatar.path
    end
  end

  context "An attachment with a :rails_env interpolation" do
    setup do
      @rails_env = "blah"
      @id = 1024
      rebuild_model :path => ":rails_env/:id.png"
      @dummy = Dummy.new
      @dummy.stubs(:id).returns(@id)
      @file = StringIO.new(".")
      @dummy.avatar = @file
      Rails.stubs(:env).returns(@rails_env)
    end

    should "return the proper path" do
      assert_equal "#{@rails_env}/#{@id}.png", @dummy.avatar.path
    end
  end

  context "An attachment with a default style and an extension interpolation" do
    setup do
      @attachment = attachment :path => ":basename.:extension",
                               :styles => { :default => ["100x100", :png] },
                               :default_style => :default
      @attachment.post_processing = false
      @file = StringIO.new("...")
      @file.stubs(:original_filename).returns("file.jpg")
    end

    should "return the right extension for the path" do
      @attachment.assign(@file)
      assert_equal "file.png", @attachment.path
    end

    context "fast upload via nginx" do
      should "return the right extension for the path" do
        Tempfile.create do |tempfile|
          content = "file contents"
          tempfile.write(content)
          upload = { 'original_name' => 'foo.jpg', 'content_type' => 'application/jpg', 'filepath' => tempfile.tap(&:rewind).path }
          @attachment.assign(upload)
          assert_equal "foo.png", @attachment.path
          assert_equal content, @attachment.queued_for_write[:original].tap(&:rewind).read
        end
      end
    end
  end

  context "An attachment with both 'normal' and hash-style styles" do
    setup do
      rebuild_model :styles => {
                      :normal => ["50x50#", :png],
                      :hash => { :geometry => "50x50#", :format => :png }
                    }
      @dummy = Dummy.new
      @attachment = @dummy.avatar
    end

    [:processors, :whiny, :convert_options, :geometry, :format].each do |field|
      should "have the same #{field} field" do
        assert_equal @attachment.styles[:normal][field], @attachment.styles[:hash][field]
      end
    end
  end

  class Paperclip::Test < Paperclip::Processor; end

  context "An attachment with multiple processors" do
    setup do
      @style_params = { :once => {:one => 1, :two => 2} }
      rebuild_model :processors => [:thumbnail, :test], :styles => @style_params
      @dummy = Dummy.new
      @file = StringIO.new("...")
      @file.stubs(:to_tempfile).returns(@file)
      Paperclip::Test.stubs(:make).returns(@file)
      Paperclip::Thumbnail.stubs(:make).returns(@file)
      @dummy.avatar.stubs(:content_type).returns('image/wow')
    end

    context "when assigned" do
      setup { @dummy.avatar = @file }

      before_should "call #make on all specified processors" do
        expected_params = @style_params[:once].merge({:processors => [:thumbnail, :test], :whiny => true, :convert_options => ""})
        Paperclip::Thumbnail.expects(:make).with(@file, expected_params, @dummy.avatar).returns(@file)
        Paperclip::Test.expects(:make).with(@file, expected_params, @dummy.avatar).returns(@file)
      end

      before_should "call #make with attachment passed as third argument" do
        expected_params = @style_params[:once].merge({:processors => [:thumbnail, :test], :whiny => true, :convert_options => ""})
        Paperclip::Test.expects(:make).with(@file, expected_params, @dummy.avatar).returns(@file)
      end
    end
  end

  context "An attachment with no processors defined" do
    setup do
      rebuild_model :processors => [], :styles => {:something => 1}
      @dummy = Dummy.new
      @file = StringIO.new("...")
      @dummy.avatar.stubs(:content_type).returns('image/wow')
    end
    should "raise when assigned to" do
      assert_raises(RuntimeError){ @dummy.avatar = @file }
    end
  end

  context "Assigning an attachment" do
    setup do
      rebuild_model :styles => { :something => "100x100#" }
      @file = StringIO.new(".")
      @file.expects(:original_filename).returns("5k.png\n\n")
      @file.stubs(:content_type).returns("image/png\n\n")
      @file.stubs(:to_tempfile).returns(@file)
      @dummy = Dummy.new
      Paperclip::Thumbnail.expects(:make).returns(@file)
      @attachment = @dummy.avatar
      @dummy.avatar = @file
      @dummy.stubs(:content_type).returns('image/wow')
    end

    should "strip whitespace from original_filename field" do
      assert_equal "5k.png", @dummy.avatar.original_filename
    end

    should "strip whitespace from content_type field" do
      assert_equal "image/png", @dummy.avatar.instance.avatar_content_type
    end
  end

  context "An attachment" do
    setup do
      @old_defaults = Paperclip::Attachment.default_options.dup
      Paperclip::Attachment.default_options.merge!({
        :path => "./tmp/:attachment/:class/:style/:id/:basename.:extension"
      })
      FileUtils.rm_rf("tmp")
      rebuild_model
      @instance = Dummy.new
      @attachment = Paperclip::Attachment.build_class(:avatar).new(@instance)
      @file = File.new(File.join(File.dirname(__FILE__),
                                 "fixtures",
                                 "5k.png"), 'rb')
    end

    teardown do
      @file&.close
      Paperclip::Attachment.default_options.merge!(@old_defaults)
    end

    should "raise if there are not the correct columns when you try to assign" do
      @other_attachment = Paperclip::Attachment.build_class(:not_here).new(@instance)
      assert_raises(Paperclip::PaperclipError) do
        @other_attachment.assign(@file)
      end
    end

    should "return its default_url when no file assigned" do
      assert @attachment.to_file.nil?
      assert_equal "/avatars/original/missing.png", @attachment.url
      assert_equal "/avatars/blah/missing.png", @attachment.url(:blah)
    end

    should "return nil as path when no file assigned" do
      assert @attachment.to_file.nil?
      assert_equal nil, @attachment.path
      assert_equal nil, @attachment.path(:blah)
    end

    context "with a file assigned in the database" do
      setup do
        @attachment.stubs(:instance_read).with(:file_name).returns("5k.png")
        @attachment.stubs(:instance_read).with(:content_type).returns("image/png")
        @attachment.stubs(:instance_read).with(:file_size).returns(12345)
        now = Time.now
        Time.stubs(:now).returns(now)
        @attachment.stubs(:instance_read).with(:updated_at).returns(Time.now)
      end

      should "return a correct url even if the file does not exist" do
        assert_nil @attachment.to_file
        assert_match %r{^/system/avatars/#{@instance.id}/blah/5k\.png}, @attachment.url(:blah)
      end

      should "make sure the updated_at mtime is in the url if it is defined" do
        assert_match %r{#{Time.now.to_i}$}, @attachment.url(:blah)
      end

      should "make sure the updated_at mtime is NOT in the url if false is passed to the url method" do
        assert_no_match %r{#{Time.now.to_i}$}, @attachment.url(:blah, false)
      end

      context "with the updated_at field removed" do
        setup do
          @attachment.stubs(:instance_read).with(:updated_at).returns(nil)
        end

        should "only return the url without the updated_at when sent #url" do
          assert_match "/avatars/#{@instance.id}/blah/5k.png", @attachment.url(:blah)
        end
      end

      should "return the proper path when filename has a single .'s" do
        assert_equal "./tmp/avatars/dummies/original/#{@instance.id}/5k.png", @attachment.path
      end

      should "return the proper path when filename has multiple .'s" do
        @attachment.stubs(:instance_read).with(:file_name).returns("5k.old.png")
        assert_equal "./tmp/avatars/dummies/original/#{@instance.id}/5k.old.png", @attachment.path
      end

      context "when expecting three styles" do
        setup do
          styles = {:styles => { :large  => ["400x400", :png],
                                 :medium => ["100x100", :gif],
                                 :small => ["32x32#", :jpg]}}
          @attachment = Paperclip::Attachment.build_class(:avatar, styles).new(@instance)
        end

        context "and assigned a file" do
          setup do
            now = Time.now
            Time.stubs(:now).returns(now)
            @attachment.assign(@file)
          end

          should "be dirty" do
            assert @attachment.dirty?
          end

          context "and saved" do
            setup do
              @attachment.save
            end

            should "return the real url" do
              file = @attachment.to_file
              assert file
              assert_match %r{^/system/avatars/#{@instance.id}/original/5k\.png}, @attachment.url
              assert_match %r{^/system/avatars/#{@instance.id}/small/5k\.jpg}, @attachment.url(:small)
              file.close
            end

            should "commit the files to disk" do
              [:large, :medium, :small].each do |style|
                io = @attachment.to_io(style)
                assert File.exist?(io)
                assert ! io.is_a?(::Tempfile)
                io.close
              end
            end

            should "save the files as the right formats and sizes" do
              [[:large, 400, 61, "PNG"],
               [:medium, 100, 15, "GIF"],
               [:small, 32, 32, "JPEG"]].each do |style|
                cmd = %Q[identify -format "%w %h %b %m" "#{@attachment.path(style.first)}"]
                out = `#{cmd}`
                width, height, _size, format = out.split(" ")
                assert_equal style[1].to_s, width.to_s
                assert_equal style[2].to_s, height.to_s
                assert_equal style[3].to_s, format.to_s
              end
            end

            should "still have its #file attribute not be nil" do
              assert ! (file = @attachment.to_file).nil?
              file.close
            end

            context "and trying to delete" do
              setup do
                @existing_names = @attachment.styles.keys.collect do |style|
                  @attachment.path(style)
                end
              end

              should "delete the files after assigning nil" do
                @attachment.assign nil
                @attachment.save
                @existing_names.each { |f| assert !File.exist?(f) }
              end

              should "delete the files when you call #clear and #save" do
                @attachment.clear
                @attachment.save
                @existing_names.each { |f| assert !File.exist?(f) }
              end

              should "delete the files when you call #delete" do
                @attachment.destroy
                @existing_names.each { |f| assert !File.exist?(f) }
              end
            end
          end
        end
      end
    end

    context "when trying a nonexistant storage type" do
      should "not be able to find the module" do
        assert_raise(NameError) { rebuild_model storage: :not_here }
      end
    end
  end

  context "An attachment with only a avatar_file_name column" do
    setup do
      ActiveRecord::Base.connection.create_table :dummies, :force => true do |table|
        table.column :avatar_file_name, :string
      end
      rebuild_class
      @dummy = Dummy.new
      @file = File.new(File.join(File.dirname(__FILE__), "fixtures", "5k.png"), 'rb')
    end

    teardown { @file.close }

    should "not error when assigned an attachment" do
      assert_nothing_raised { @dummy.avatar = @file }
    end

    should "return the time when sent #avatar_updated_at" do
      now = Time.now
      Time.stubs(:now).returns(now)
      @dummy.avatar = @file
      assert now.to_s, @dummy.avatar.updated_at.to_s
    end

    should "return nil when reloaded and sent #avatar_updated_at" do
      @dummy.save
      @dummy.reload
      assert_nil @dummy.avatar.updated_at
    end

    should "return the right value when sent #avatar_file_size" do
      @dummy.avatar = @file
      assert_equal @file.size, @dummy.avatar.size
    end

    context "and avatar_updated_at column" do
      setup do
        ActiveRecord::Base.connection.add_column :dummies, :avatar_updated_at, :timestamp
        rebuild_class
        @dummy = Dummy.new
      end

      should "not error when assigned an attachment" do
        assert_nothing_raised { @dummy.avatar = @file }
      end

      should "return the right value when sent #avatar_updated_at" do
        now = Time.now
        Time.stubs(:now).returns(now)
        @dummy.avatar = @file
        assert_equal now.to_i, @dummy.avatar.updated_at
      end
    end

    context "and avatar_content_type column" do
      setup do
        ActiveRecord::Base.connection.add_column :dummies, :avatar_content_type, :string
        rebuild_class
        @dummy = Dummy.new
      end

      should "not error when assigned an attachment" do
        assert_nothing_raised { @dummy.avatar = @file }
      end

      should "return the right value when sent #avatar_content_type" do
        @dummy.avatar = @file
        assert_equal "image/png", @dummy.avatar.content_type
      end
    end

    context "and avatar_file_size column" do
      setup do
        ActiveRecord::Base.connection.add_column :dummies, :avatar_file_size, :integer
        rebuild_class
        @dummy = Dummy.new
      end

      should "not error when assigned an attachment" do
        assert_nothing_raised { @dummy.avatar = @file }
      end

      should "return the right value when sent #avatar_file_size" do
        @dummy.avatar = @file
        assert_equal @file.size, @dummy.avatar.size
      end

      should "return the right value when saved, reloaded, and sent #avatar_file_size" do
        @dummy.avatar = @file
        @dummy.save
        @dummy = Dummy.find(@dummy.id)
        assert_equal @file.size, @dummy.avatar.size
      end
    end
  end
end
