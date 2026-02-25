# frozen_string_literal: true

$:.push File.expand_path('lib', __dir__)

# Maintain your gem's version:
require 'devise_token_auth/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'devise_token_auth_multi_email'
  s.version     = DeviseTokenAuth::VERSION
  s.authors     = ['Lynn Hurley', 'Micah Gideon Modell']
  s.email       = ['lynn.dylan.hurley@gmail.com', 'micah.modell@gmail.com']
  s.homepage    =
  'https://github.com/mgmodell/devise_token_auth_multi_email'
  s.summary     = 'Token based authentication for rails. Uses Devise + OmniAuth + multiple emails.'
  s.description = 'For use with client side single page apps such as ' +
    'the venerable https://github.com/lynndylanhurley/ng-token-auth. ' +
    'This version is distinct as it supports multiple email ' +
    'addresses per user.'
  s.license     = 'WTFPL'

  s.files      = Dir['{app,config,db,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']
  s.test_files = Dir['test/**/*']
  s.test_files.reject! do |file|
    file.match(/[.log|.sqlite3]$/)
  end

  s.required_ruby_version = ">= 2.3.0"


  s.add_dependency 'rails', '>= 4.2.0', '<= 8.2'
  # s.add_dependency 'devise', '> 3.5.2', '< 6.0'
  s.add_dependency 'bcrypt', '~> 3.0'
  s.add_dependency 'devise-multi_email_revived', '~> 3.1'

  s.add_development_dependency 'appraisal'
  s.add_development_dependency 'sqlite3', '~> 1.4'
  s.add_development_dependency 'pg'
  s.add_development_dependency 'mysql2'
  s.add_development_dependency 'mongoid', '>= 4', '< 8'
  s.add_development_dependency 'mongoid-locker', '>= 1.0', '< 3.0'
end
