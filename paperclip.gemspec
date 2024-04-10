# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = %q{paperclip}
  s.version = "2.2.9.2"
  s.required_ruby_version = ">= 2.3.0" # rubocop:disable Gemspec/RequiredRubyVersion
  s.authors = ["Jon Yurek"]
  s.date = %q{2009-06-18}
  s.email = %q{jyurek@thoughtbot.com}
  s.extra_rdoc_files = ["README.rdoc"]
  s.files = `git ls-files -z`.split("\x0").reject do |file|
    file.start_with?('.') || file.match?(%r{^(test|gemfiles)/}) ||
      file.match?(/docker-compose.yml|Appraisals|Gemfile|Rakefile/)
  end
  s.homepage = %q{http://www.thoughtbot.com/projects/paperclip}
  s.rdoc_options = ["--line-numbers", "--inline-source"]
  s.require_paths = ["lib"]
  s.requirements = ["ImageMagick"]
  s.rubyforge_project = %q{paperclip}
  s.summary = %q{File attachments as attributes for ActiveRecord}

  s.add_dependency 'activesupport', [">= 5.0", '< 7.2']
  s.add_dependency 'addressable'
  s.add_dependency 'fastimage'
end
