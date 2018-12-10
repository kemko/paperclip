require 'test_helper'
require 'fog/local'
require 'sidekiq'
require 'sidekiq/testing'

require 'delayed_paperclip'
DelayedPaperclip::Railtie.insert

class FakeModel
  attr_accessor :synced_to_store_1, :synced_to_store_2
end

class CachedStorageTest < Test::Unit::TestCase
  TEST_ROOT = Pathname(__dir__).join('test')

  def fog_directory(suffix)
    Fog::Storage.new(provider: 'Local', local_root: TEST_ROOT.join(suffix.to_s))
      .directories.new(key: '', public: true)
  end

  def stub_file(name, content)
    StringIO.new(content).tap { |x| x.stubs(:original_filename).returns(name) }
  end

  setup do
    rebuild_model(
      storage: :cached,
      key: ':filename',
      url: {
        cache: 'http://cache.local/:key',
        store: 'http://store.local/:key'
      },
      cache: fog_directory(:cache),
      stores: {
        store_1: fog_directory(:store_1),
        store_2: fog_directory(:store_2),
      }
    )
    modify_table(:dummies) do |t|
      t.boolean :avatar_synced_to_store_1, null: false, default: false
      t.boolean :avatar_synced_to_store_2, null: false, default: false
    end
    @instance = Dummy.create
  end

  teardown { TEST_ROOT.rmtree if TEST_ROOT.exist? }

  context 'assigning file' do
    setup { Sidekiq::Testing.fake! }

    should 'write to cache and enqueue jobs' do
      @instance.update!(avatar: stub_file('test.txt', 'qwe'))
      @instance.reload
      attachment = @instance.avatar
      key = attachment.key
      assert_equal true, attachment.exists?
      assert_equal false, attachment.class.directory_for(:cache).files.head(key).nil?
      assert_equal true, attachment.class.directory_for(:store_1).files.head(key).nil?
      assert_equal true, attachment.class.directory_for(:store_2).files.head(key).nil?
      assert_equal 'http://cache.local/test.txt', attachment.url(:original, false)
    end

    context 'with inline jobs' do
      setup { Sidekiq::Testing.inline! }
      teardown { Sidekiq::Testing.fake! }

      should 'write to permanent stores and crear cache' do
        @instance.update!(avatar: stub_file('test.txt', 'qwe'))
        @instance.reload
        attachment = @instance.avatar
        key = attachment.key
        assert_equal false, attachment.exists?
        assert_equal true, attachment.class.directory_for(:cache).files.head(key).nil?
        assert_equal false, attachment.class.directory_for(:store_1).files.head(key).nil?
        assert_equal false, attachment.class.directory_for(:store_2).files.head(key).nil?
        assert_equal 'http://store.local/test.txt', attachment.url(:original, false)
      end
    end
  end
end
