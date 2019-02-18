require 'active_support/version'

module Paperclip
  module CallbackCompatability
    module_function

    def install_to(base)
      mod = base.respond_to?(:set_callback) ? Rails3 : Rails21
      base.extend(mod::Defining)
      base.send(:include, mod::Running)
    end

    module Rails21
      module Defining
        def define_paperclip_callbacks(*args)
          args.each do |callback|
            define_callbacks("before_#{callback}")
            define_callbacks("after_#{callback}")
          end
        end
      end

      module Running
        def run_paperclip_callbacks(callback, opts = nil, &blk)
          # The overall structure of this isn't ideal since after callbacks run even if
          # befores return false. But this is how rails 3's callbacks work, unfortunately.
          if run_callbacks(:"before_#{callback}"){ |result, object| result == false } != false
            blk.call
          end
          run_callbacks(:"after_#{callback}"){ |result, object| result == false }
        end
      end
    end

    module Rails3
      module Defining
        rails_version = Gem::Version.new(ActiveSupport::VERSION::STRING)
        CALLBACK_OPTIONS =
          if rails_version >= Gem::Version.new('5.0')
            {}
          elsif rails_version >= Gem::Version.new('4.1')
            {terminator: ->(target, result) { result == false }}
          else
            {terminator: 'result == false'}
          end

        def define_paperclip_callbacks(*callbacks)
          define_callbacks *callbacks.flatten, CALLBACK_OPTIONS
          callbacks.map(&:to_sym).each do |callback|
            define_singleton_method "before_#{callback}" do |*args, &blk|
              set_callback(callback, :before, *args, &blk)
            end

            define_singleton_method "after_#{callback}" do |*args, &blk|
              set_callback(callback, :after, *args, &blk)
            end
          end
        end
      end

      module Running
        def run_paperclip_callbacks(callback, &block)
          run_callbacks(callback, &block)
        end
      end
    end
  end
end

