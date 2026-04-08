# frozen_string_literal: true

begin
  require 'bundler/setup'
rescue LoadError
  puts 'You must `gem install bundler` and `bundle install` to run rake tasks'
end

require 'rdoc/task'

RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'DeviseTokenAuthMultiEmail'
  rdoc.options << '--line-numbers'
  rdoc.rdoc_files.include('README.rdoc')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

APP_RAKEFILE = File.expand_path('test/dummy/Rakefile', __dir__)
load 'rails/tasks/engine.rake'

Bundler::GemHelper.install_tasks

# Custom test task to avoid minitest-rails SIGTRAP issue  
desc 'Run all tests'
task :test do
  sh 'find test -name "*_test.rb" -exec bundle exec ruby -I lib:test {} \;'
end

task default: :test

require 'rubocop/rake_task'

desc 'Run RuboCop'
RuboCop::RakeTask.new(:rubocop) do |task|
  task.formatters = %w[fuubar offenses worst]
  task.fail_on_error = false # don't abort rake on failure
end
