module Paperclip
  class Railtie < Rails::Railtie
    initializer 'paperclip.railtie.configure' do
      if defined? Rails.root
        Dir.glob(File.join(File.expand_path(Rails.root), "lib", "paperclip_processors", "*.rb")).each do |processor|
          require processor
        end
      end
    end
  end
end
