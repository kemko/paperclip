# frozen_string_literal: true

require 'test_helper'
require 'sidekiq'
require 'sidekiq/testing'
require 'aws-sdk-s3'
require 'base64'

require 'delayed_paperclip'
DelayedPaperclip::Railtie.insert

# rubocop:disable Naming/VariableNumber

class FakeModel
  attr_accessor :synced_to_store_1, :synced_to_store_2
end

class NoCacheS3Test < Test::Unit::TestCase
  TEST_ROOT = Pathname(__dir__).join('test')

  def stub_file(name, content)
    StringIO.new(content).tap { |string_io| string_io.stubs(:original_filename).returns(name) }
  end

  setup do
    rebuild_model(
      storage: :no_cache_s3,
      key: ':filename',
      url: 'http://store.local/:key',
      stores: {
        store_1: { access_key_id: '123', secret_access_key: '123', region: 'r', bucket: 'buck' },
        store_2: { access_key_id: '456', secret_access_key: '456', region: 'r', bucket: 'buck' }
      },
      styles: {
        original: { geometry: '4x4>', processors: %i[thumbnail optimizer] },
        medium: '3x3',
        small: { geometry: '2x2', processors: [:recursive_thumbnail], thumbnail: :medium },
        micro: { geometry: '1x1', processors: [:recursive_thumbnail], thumbnail: :small }
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
    Dummy::AvatarAttachment.any_instance.stubs(:to_file).returns(
      stub_file('pixel.gif', Base64.decode64('R0lGODlhAQABAIABAP///wAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw'))
    )
  end

  teardown { TEST_ROOT.rmtree if TEST_ROOT.exist? }

  context 'assigning file' do
    setup { Sidekiq::Testing.fake! }

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
      assert_equal 'http://store.local/test.txt', attachment.url(:original, false)
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
        assert_equal 'http://store.local/test.txt', attachment.url(:original, false)
      end
    end
  end

  context "reprocess" do
    setup do
      Sidekiq::Testing.fake!
      @instance.update_columns avatar_file_name: 'foo.gif', avatar_content_type: 'image/gif'
    end

    should "delete tmp files" do
      @store1_stub.expects(:put_object).times(1 + (@instance.avatar.options[:styles].keys - [:original]).size)
      # Paperclip.expects(:log).with { puts "Log: #{_1}"; true }.at_least(3)
      existing_files = Dir.children(Dir.tmpdir)
      @instance.avatar.reprocess!
      leftover_files = (Dir.children(Dir.tmpdir) - existing_files).sort
      assert_empty(leftover_files)
    end
  end

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
