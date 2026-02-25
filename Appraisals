# frozen_string_literal: true

[
  { name: '7-0', version: '7.0' }
].each do |rails|
  appraise "rails-#{rails[:name]}" do
    gem 'rails', "~> #{rails[:version]}"

    gem 'sqlite3', '~> 1.3.6'
    gem 'mysql2'
    gem 'pg'
  end
end

[
  { name: '6-0', ruby: '3.1.2', rails: '6.0', mongoid: '7.0' },
  { name: '7-0', ruby: '3.1.2', rails: '7.0', mongoid: '7.0' }
].each do |set|
  appraise "rails-#{set[:name]}-mongoid-#{set[:mongoid][0]}" do
    gem 'rails', "~> #{set[:rails]}"

    gem 'mongoid', "~> #{set[:mongoid]}"
    gem 'mongoid-locker', '~> 1.0'
  end
end
