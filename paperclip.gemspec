# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = %q{paperclip}
  s.version = "2.2.9.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Jon Yurek"]
  s.date = %q{2009-06-18}
  s.email = %q{jyurek@thoughtbot.com}
  s.extra_rdoc_files = ["README.rdoc"]
  s.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|gemfiles)/}) }
  s.homepage = %q{http://www.thoughtbot.com/projects/paperclip}
  s.rdoc_options = ["--line-numbers", "--inline-source"]
  s.require_paths = ["lib"]
  s.requirements = ["ImageMagick"]
  s.rubyforge_project = %q{paperclip}
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{File attachments as attributes for ActiveRecord}

  s.add_dependency 'activesupport', '< 7.1'
  s.add_dependency 'fastimage'
end
