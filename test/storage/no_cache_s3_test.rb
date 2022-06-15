# frozen_string_literal: true

require 'test_helper'
require 'sidekiq'
require 'sidekiq/testing'
require 'aws-sdk-s3'

require 'delayed_paperclip'
DelayedPaperclip::Railtie.insert

# rubocop:disable Naming/VariableNumber

class FakeModel
  attr_accessor :synced_to_store_1, :synced_to_store_2
end

class NoCachedS3Test < Test::Unit::TestCase
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
      }
    )
    modify_table(:dummies) do |table|
      table.boolean :avatar_synced_to_store_1, null: false, default: false
      table.boolean :avatar_synced_to_store_2, null: false, default: false
    end
    @instance = Dummy.create
    @store1_stub = mock
    @store2_stub = mock
    @instance.avatar.class.stubs(:stores).returns({ store_1: @store1_stub, store_2: @store2_stub })
    Dummy::AvatarAttachment.any_instance.stubs(:to_file).returns(stub_file('test.txt', 'qwe'))
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
        @instance.reload
        attachment = @instance.avatar
        assert_equal 'http://store.local/test.txt', attachment.url(:original, false)
      end
    end
  end
end

# rubocop:enable Naming/VariableNumber
