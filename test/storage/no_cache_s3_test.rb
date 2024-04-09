# frozen_string_literal: true

require 'test_helper'
require 'sidekiq'
require 'sidekiq/testing'
require 'aws-sdk-s3'
require 'base64'

require 'delayed_paperclip'
DelayedPaperclip::Railtie.insert

# rubocop:disable Naming/VariableNumber

class NoCacheS3Test < Test::Unit::TestCase
  TEST_ROOT = Pathname(__dir__).join('test')

  def stub_file(name, content)
    StringIO.new(content).tap { |string_io| string_io.stubs(:original_filename).returns(name) }
  end

  setup do
    rebuild_model(
      storage: :no_cache_s3,
      key: "dummy_imgs/:id/:style-:filename",
      url: 'http://store.local/:key',
      stores: {
        store_1: { access_key_id: '123', secret_access_key: '123', region: 'r', bucket: 'buck' },
        store_2: { access_key_id: '456', secret_access_key: '456', region: 'r', bucket: 'buck' }
      },
      # styles: {
      #   original: { geometry: '4x4>', processors: %i[thumbnail optimizer] }, # '4x4>' to limit size
      #   medium: '3x3',
      #   small: { geometry: '2x2', processors: [:recursive_thumbnail], thumbnail: :medium },
      #   micro: { geometry: '1x1', processors: [:recursive_thumbnail], thumbnail: :small }
      # }
      styles: {
        original: { geometry: '2048x2048>', processors: %i[thumbnail optimizer] },
        large: '480x480',
        medium: '240x240',
        compact: { geometry: '160x160', processors: [:recursive_thumbnail], thumbnail: :medium },
        thumb: { geometry: '100x100', processors: [:recursive_thumbnail], thumbnail: :compact },
        micro: { geometry: '48x48',   processors: [:recursive_thumbnail], thumbnail: :thumb }
      }
    )
    modify_table(:dummies) do |table|
      table.boolean :avatar_synced_to_store_1, null: false, default: false
      table.boolean :avatar_synced_to_store_2, null: false, default: false
    end
    @instance = Dummy.create
    @store1_stub = mock("store1")
    @store2_stub = mock("store2")
    @store1_stub.stubs(:url).returns('http://store.local')
    @store2_stub.stubs(:url).returns('http://store.local')
    @instance.avatar.class.stubs(:stores).returns({ store_1: @store1_stub, store_2: @store2_stub })
    @gif_pixel = Base64.decode64('R0lGODlhAQABAIABAP///wAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw')
  end

  teardown { TEST_ROOT.rmtree if TEST_ROOT.exist? }

  context 'assigning file' do
    setup do
      Sidekiq::Testing.fake!
      Dummy::AvatarAttachment.any_instance.stubs(:to_file).returns(stub_file('pixel.gif', @gif_pixel))
    end

    should 'set synced_fields to false' do
      @instance.avatar_synced_to_store_1 = true
      @instance.avatar_synced_to_store_2 = true
      @instance.avatar = stub_file('test.txt', 'qwe')
      assert_equal false, @instance.avatar_synced_to_store_1
      assert_equal false, @instance.avatar_synced_to_store_2
    end

    should 'write to main store and enqueue jobs to copy to others' do
      @store1_stub.expects(:put_object).once
      @store2_stub.expects(:put_object).never
      @instance.update!(avatar: stub_file('test.txt', 'qwe'))
      @instance.run_callbacks(:commit)
      @instance.reload
      attachment = @instance.avatar
      assert_equal 'http://store.local/dummy_imgs/1/original-test.txt', attachment.url(:original, false)
    end

    context 'with inline jobs' do
      setup { Sidekiq::Testing.inline! }
      teardown { Sidekiq::Testing.fake! }

      should 'write to all permanent stores' do
        @store1_stub.expects(:put_object).once
        @store2_stub.expects(:put_object).once
        @instance.update!(avatar: stub_file('test.txt', 'qwe'))
        @instance.run_callbacks(:commit)
        @instance.reload
        attachment = @instance.avatar
        assert_equal 'http://store.local/dummy_imgs/1/original-test.txt', attachment.url(:original, false)
      end
    end
  end

  def assert_no_leftover_tmp
    existing_files = Dir.children(Dir.tmpdir)
    yield
    leftover_files = (Dir.children(Dir.tmpdir) - existing_files).sort
    assert_empty(leftover_files)
  end

  context "reprocess" do
    setup do
      Sidekiq::Testing.fake!
      Dummy::AvatarAttachment.any_instance.stubs(:download_from_store).returns(stub_file('pixel.gif', @gif_pixel))
      @instance.update_columns avatar_file_name: 'foo.gif', avatar_content_type: 'image/gif',
                               avatar_synced_to_store_1: true
    end

    should "delete tmp files" do
      @store1_stub.expects(:put_object).times(1 + (@instance.avatar.options[:styles].keys - [:original]).size)
      # Paperclip.expects(:log).with { puts "Log: #{_1}"; true }.at_least(3)
      assert_no_leftover_tmp { @instance.avatar.reprocess! }
    end

    context "with download_by_url" do
      setup do
        @instance.avatar.class.instance_variable_set(:@download_by_url, true)
        @instance.avatar.stubs(:presigned_url).returns("http://example.com/some_file") # чтобы не стабать store.object.presigned_uri
        require 'open-uri'
        # правильнее было бы webmock притащить и сам запрос застабить, но ради одного теста жирновато
        Net::HTTP.any_instance.stubs(:start).yields(nil)
        resp = Net::HTTPSuccess.new(1.1, 200, 'ok')
        str = @gif_pixel.dup
        str.stubs(:clear) # чтобы не попортить вторым вызовом
        # начиная с OpenURI::Buffer::StringMax open-uri генерит tempfile
        resp.stubs(:read_body).multiple_yields(str, "\0" * OpenURI::Buffer::StringMax)
        Net::HTTP.any_instance.stubs(:request).yields(resp)
      end

      should "delete tmp files" do
        @store1_stub.expects(:put_object).times(1 + (@instance.avatar.options[:styles].keys - [:original]).size)
        assert_no_leftover_tmp { @instance.avatar.reprocess! }
      end
    end
  end

  context "with delayed_paperclip process_in_background" do # rubocop:disable Style/MultilineIfModifier
    setup do
      Dummy.process_in_background(:avatar)
      Sidekiq::Testing.fake!
      Sidekiq::Queues.clear_all

      # local minio
      bucket = ::Aws::S3::Resource.new(client: ::Aws::S3::Client.new(
        access_key_id: 'test', secret_access_key: 'testpassword',
        endpoint: 'http://localhost:9002', region: 'laplandia', force_path_style: true
      )).bucket("bucketname")
      @instance.avatar.class.stubs(:stores).returns({ store_1: bucket })
    end

    should "add job and process" do
      # @store1_stub.expects(:put_object).once
      # @store2_stub.expects(:put_object).never
      assert_no_leftover_tmp do
        @instance.update!(avatar: stub_file('pixel.gif', @gif_pixel))
        # @instance.update!(avatar: File.open('sample_notebook_1.jpg'))
      end
      assert_equal(1, DelayedPaperclip::Jobs::Sidekiq.jobs.size)

      @instance = Dummy.find(@instance.id)
      assert_no_leftover_tmp { DelayedPaperclip::Jobs::Sidekiq.perform_one }
    end
  end unless ENV['CI']

  context 'generating presigned_url' do
    setup do
      Dummy::AvatarAttachment.any_instance.stubs(:storage_url).returns('http://домен.pф/ключ?param1=параметр')
      object_stub = mock
      object_stub.stubs(:presigned_url).returns('http://другой.домен?param2=param_value')
      @store1_stub.stubs(:object).returns(object_stub)
    end

    should 'escape cyrillic and work' do
      @instance.avatar = stub_file('кириллица.txt', 'qwe')
      assert_equal(
        "http://xn--d1acufc.xn--p-eub/%D0%BA%D0%BB%D1%8E%D1%87?"\
        "param1=%D0%BF%D0%B0%D1%80%D0%B0%D0%BC%D0%B5%D1%82%D1%80&param2=param_value",
        @instance.avatar.send(:presigned_url, :original)
      )
    end
  end
end

# rubocop:enable Naming/VariableNumber
