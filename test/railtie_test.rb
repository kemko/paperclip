# frozen_string_literal: true

require 'test_helper'

class RailtieTest < Test::Unit::TestCase
  should "load processors" do
    FileUtils.mkdir_p('tmp/rails/lib/paperclip_processors')
    Rails.root.join('lib/paperclip_processors/some_custom_processor.rb').write <<~RUBY
      class Paperclip::SomeCustomProcessor < Paperclip::Processor
      end
    RUBY
    Paperclip::Railtie.initializers.each(&:run)
    assert defined?(Paperclip::SomeCustomProcessor)
  end

  should "load rake tasks" do
    require 'rake'
    require 'rake/testtask'

    Rails.application.load_tasks
    assert_equal Rake::Task, Rake.application["paperclip:refresh:thumbnails"].class
  end
end
