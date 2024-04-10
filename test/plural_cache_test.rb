require 'test_helper'

class PluralCacheTest < Test::Unit::TestCase
  class BigBox; end # rubocop:disable Lint/EmptyClass

  should 'cache pluralizations' do
    cache = Paperclip::Interpolations::PluralCache.new
    symbol = :box

    first = cache.pluralize_symbol(symbol)
    second = cache.pluralize_symbol(symbol)
    assert_equal first, second
  end

  should 'cache pluralizations and underscores' do
    cache = Paperclip::Interpolations::PluralCache.new
    klass = BigBox

    first = cache.underscore_and_pluralize_class(klass)
    second = cache.underscore_and_pluralize_class(klass)
    assert_equal first, second
  end

  should 'pluralize words' do
    cache = Paperclip::Interpolations::PluralCache.new
    assert_equal 'boxes', cache.pluralize_symbol(:box)
  end

  should 'pluralize and underscore words' do
    cache = Paperclip::Interpolations::PluralCache.new
    klass = BigBox
    assert_equal 'plural_cache_test/big_boxes', cache.underscore_and_pluralize_class(klass)
  end
end
