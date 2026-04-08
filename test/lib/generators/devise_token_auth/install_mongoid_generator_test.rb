# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'generators/devise_token_auth/install_mongoid_generator'

module DeviseTokenAuth
  class InstallMongoidGeneratorTest < Rails::Generators::TestCase
    tests InstallMongoidGenerator
    destination Rails.root.join('tmp/generators')

    describe 'default values, clean install' do
      setup :prepare_destination

      before do
        run_generator
      end

      test 'user model is created from mongoid template' do
        assert_file 'app/models/user.rb'
      end

      test 'created user model includes Mongoid::Document' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/include Mongoid::Document/, model)
        end
      end

      test 'created user model includes Mongoid::Timestamps' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/include Mongoid::Timestamps/, model)
        end
      end

      test 'created user model includes Mongoid::Locker' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/include Mongoid::Locker/, model)
        end
      end

      test 'created user model declares locker fields' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/field :locker_locked_at/, model)
          assert_match(/field :locker_locked_until/, model)
        end
      end

      test 'created user model declares required devise token auth fields' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/field :provider/, model)
          assert_match(/field :uid/, model)
          assert_match(/field :tokens/, model)
        end
      end

      test 'created user model includes devise' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/devise :database_authenticatable/, model)
        end
      end

      test 'created user model includes DeviseTokenAuth concern' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/include DeviseTokenAuth::Concerns::User/, model)
        end
      end

      test 'created user model declares uid_provider_index' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/uid_provider_index/, model)
        end
      end

      test 'initializer is created' do
        assert_file 'config/initializers/devise_token_auth.rb'
      end

      test 'subsequent runs raise no errors' do
        run_generator
      end
    end

    describe 'existing user model' do
      setup :prepare_destination

      before do
        @dir = File.join(destination_root, 'app', 'models')
        @fname = File.join(@dir, 'user.rb')
        FileUtils.mkdir_p(@dir)

        File.open(@fname, 'w') do |f|
          f.write <<-'RUBY'
            class User

              def whatever
                puts 'whatever'
              end
            end
          RUBY
        end

        run_generator
      end

      test 'concern is injected into existing model' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/include DeviseTokenAuth::Concerns::User/, model)
        end
      end

      test 'mongoid locker fields are injected into existing model' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/include Mongoid::Locker/, model)
          assert_match(/field :locker_locked_at/, model)
          assert_match(/field :locker_locked_until/, model)
        end
      end

      test 'required fields are injected into existing model' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/field :provider/, model)
          assert_match(/field :uid/, model)
          assert_match(/field :tokens/, model)
        end
      end

      test 'devise declaration is injected into existing model' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/devise :database_authenticatable/, model)
        end
      end

      test 'index declaration is injected into existing model' do
        assert_file 'app/models/user.rb' do |model|
          assert_match(/uid_provider_index/, model)
        end
      end

      test 'subsequent runs do not duplicate the concern inclusion' do
        run_generator
        assert_file 'app/models/user.rb' do |model|
          matches = model.scan(/include DeviseTokenAuth::Concerns::User/m).size
          assert_equal 1, matches
        end
      end
    end

    describe 'routes' do
      setup :prepare_destination

      before do
        @dir = File.join(destination_root, 'config')
        @fname = File.join(@dir, 'routes.rb')
        FileUtils.mkdir_p(@dir)

        File.open(@fname, 'w') do |f|
          f.write <<-RUBY
            Rails.application.routes.draw do
              patch '/chong', to: 'bong#index'
            end
          RUBY
        end

        run_generator
      end

      test 'route method is appended to routes file' do
        assert_file 'config/routes.rb' do |routes|
          assert_match(/mount_devise_token_auth_for 'User', at: 'auth'/, routes)
        end
      end

      test 'subsequent runs do not add duplicate routes' do
        run_generator
        assert_file 'config/routes.rb' do |routes|
          matches = routes.scan(/mount_devise_token_auth_for 'User', at: 'auth'/m).size
          assert_equal 1, matches
        end
      end
    end

    describe 'application controller' do
      setup :prepare_destination

      before do
        @dir = File.join(destination_root, 'app', 'controllers')
        @fname = File.join(@dir, 'application_controller.rb')
        FileUtils.mkdir_p(@dir)

        File.open(@fname, 'w') do |f|
          f.write <<-RUBY
            class ApplicationController < ActionController::Base
              def whatever
                'whatever'
              end
            end
          RUBY
        end

        run_generator
      end

      test 'controller concern is appended to application controller' do
        assert_file 'app/controllers/application_controller.rb' do |controller|
          assert_match(/include DeviseTokenAuth::Concerns::SetUserByToken/, controller)
        end
      end

      test 'subsequent runs do not duplicate the concern inclusion' do
        run_generator
        assert_file 'app/controllers/application_controller.rb' do |controller|
          matches = controller.scan(/include DeviseTokenAuth::Concerns::SetUserByToken/m).size
          assert_equal 1, matches
        end
      end
    end
  end
end
