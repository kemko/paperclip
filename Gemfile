# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo_name| "https://github.com/#{repo_name}.git" }

gemspec

gem 'pg'

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

unless defined?(Appraisal)
  gem 'appraisal'

  group :lint do
    gem 'rubocop', '~>0.81'
    gem 'rubocop-rails'
    gem 'rubocop-rspec'
    gem 'rubocop-performance'

    gem 'pronto', '>= 0.11', require: false
    gem 'pronto-brakeman', require: false
    gem 'pronto-rubocop', require: false
  end
end
