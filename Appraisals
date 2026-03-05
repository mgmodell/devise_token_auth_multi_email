# frozen_string_literal: true

[
  { name: '7-0', version: '7.0' },
  { name: '7-2', version: '7.2' },
  { name: '8-0', version: '8.0' }
].each do |rails|
    db_adapter = ENV.fetch('DB', 'sqlite' )
    appraise "rails-#{rails[:name]}" do
      gem 'rails', "~> #{rails[:version]}.0"
      gem 'mysql2'if db_adapter == 'mysql'
      gem 'pg' if db_adapter == 'postgresql'
      gem 'sqlite3', '>= 2.1' if db_adapter == 'sqlite'
    end
end

[
  { name: '7-0', ruby: '3.1.2', rails: '7.0', mongoid: '7.0' }
].each do |set|
  appraise "rails-#{set[:name]}-mongoid-#{set[:mongoid][0]}" do
    gem 'rails', "~> #{set[:rails]}.0"

    gem 'mongoid', "~> #{set[:mongoid]}"
    gem 'mongoid-locker', '~> 1.0'
  end
end
