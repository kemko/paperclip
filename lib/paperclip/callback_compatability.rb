require 'active_support/version'

module Paperclip
  module CallbackCompatability
    module_function

    def install_to(base)
      raise "#{base} does not respond to set_callback" unless base.respond_to?(:set_callback)

      base.extend(Defining)
      base.send(:include, Running)
    end

    module Defining
      def define_paperclip_callbacks(*callbacks)
        define_callbacks(*callbacks.flatten, {})
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
