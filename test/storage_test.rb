# frozen_string_literal: true

require 'test_helper'
require 'aws-sdk-s3'

class StorageTest < Test::Unit::TestCase
  context 'An attachment with no_cache_s3 storage' do
    setup do
      rebuild_model storage: :no_cache_s3,
                    key: ':filename',
                    stores: {
                      store1: { access_key_id: '123', secret_access_key: '123', region: 'r', bucket: 'buck' }
                    }
    end

    should 'be extended by the NoCacheS3 module' do
      assert Dummy.new.avatar.is_a?(Paperclip::Storage::NoCacheS3)
    end

    should 'not be extended by the Filesystem module' do
      assert !Dummy.new.avatar.is_a?(Paperclip::Storage::Filesystem)
    end
  end
end
