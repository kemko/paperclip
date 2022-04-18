module Paperclip
  class Railtie < Rails::Railtie
    initializer 'paperclip.railtie.configure' do
      if defined? Rails.root
        Dir.glob(Rails.root.join("lib/paperclip_processors/*.rb").expand_path).sort.each do |processor|
          require processor
        end
      end
    end

    rake_tasks do
      load "tasks/paperclip_tasks.rake"
    end
  end
end
