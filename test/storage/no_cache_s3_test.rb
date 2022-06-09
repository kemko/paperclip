# frozen_string_literal: true

require 'test_helper'
require 'fog/local'
require 'sidekiq'
require 'sidekiq/testing'

require 'delayed_paperclip'
DelayedPaperclip::Railtie.insert

# rubocop:disable Naming/VariableNumber

class FakeModel
  attr_accessor :synced_to_store_1, :synced_to_store_2
end

class NoCachedS3Test < Test::Unit::TestCase
  TEST_ROOT = Pathname(__dir__).join('test')

  def fog_directory(suffix)
    Fog::Storage.new(provider: 'Local', local_root: TEST_ROOT.join(suffix.to_s))
      .directories.new(key: '', public: true)
  end

  def stub_file(name, content)
    StringIO.new(content).tap { |string_io| string_io.stubs(:original_filename).returns(name) }
  end

  setup do
    rebuild_model(
      storage: :no_cache_s3,
      key: ':filename',
      url: 'http://store.local/:key',
      stores: {
        store_1: fog_directory(:store_1),
        store_2: fog_directory(:store_2)
      }
    )
    modify_table(:dummies) do |table|
      table.boolean :avatar_synced_to_store_1, null: false, default: false
      table.boolean :avatar_synced_to_store_2, null: false, default: false
    end
    @instance = Dummy.create
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
      @instance.update!(avatar: stub_file('test.txt', 'qwe'))
      @instance.reload
      attachment = @instance.avatar
      key = attachment.key
      assert_equal false, attachment.class.store_by(:store_1).files.head(key).nil?
      assert_equal true, attachment.class.store_by(:store_2).files.head(key).nil?
      assert_equal 'http://store.local/test.txt', attachment.url(:original, false)
    end

    context 'with inline jobs' do
      setup { Sidekiq::Testing.inline! }
      teardown { Sidekiq::Testing.fake! }

      should 'write to all permanent stores' do
        @instance.update!(avatar: stub_file('test.txt', 'qwe'))
        @instance.reload
        attachment = @instance.avatar
        key = attachment.key
        assert_equal false, attachment.class.store_by(:store_1).files.head(key).nil?
        assert_equal false, attachment.class.store_by(:store_2).files.head(key).nil?
        assert_equal 'http://store.local/test.txt', attachment.url(:original, false)
      end
    end
  end
end

# rubocop:enable Naming/VariableNumber
