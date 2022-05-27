# frozen_string_literal: true

require 'test_helper'

class StorageTest < Test::Unit::TestCase
  context 'An attachment with Delayeds3 storage' do
    setup do
      rebuild_model storage: :delayeds3,
                    bucket: 'testing',
                    path: ':attachment/:style/:basename.:extension',
                    yandex_credentials: {},
                    sbercloud_credentials: {}
    end

    should 'be extended by the Delayeds3 module' do
      assert Dummy.new.avatar.is_a?(Paperclip::Storage::Delayeds3)
    end

    should 'not be extended by the Filesystem module' do
      assert !Dummy.new.avatar.is_a?(Paperclip::Storage::Filesystem)
    end
  end
end
