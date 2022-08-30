# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo_name| "https://github.com/#{repo_name}.git" }

gemspec

gem 'appraisal'

gem 'fastimage'
gem 'pg', '~> 1.1.4'

gem 'aws-sdk-s3'
gem 'fog-local'

gem 'delayed_paperclip', github: 'insales/delayed_paperclip'
gem 'rails'
gem 'sidekiq'

gem 'test-unit'
gem 'mocha'
gem 'thoughtbot-shoulda', '>= 2.9.0'

gem 'pry'
gem 'pry-byebug'

gem 'addressable'

group :lint do
  gem 'rubocop', '0.81.0'
  gem 'rubocop-rails', '2.5.2'
  gem 'rubocop-rspec', '1.38.1'
  gem 'rubocop-performance', '1.5.2'

  gem 'pronto', '>= 0.11', require: false
  gem 'pronto-brakeman', require: false
  gem 'pronto-rubocop', require: false
end
