# frozen_string_literal: true

require 'test_helper'

# Tests targeting DeviseTokenAuth::Concerns::ResourceFinder in isolation.
# The concern is exercised via DeviseTokenAuth::SessionsController, which
# includes it transitively through SetUserByToken.
class DeviseTokenAuth::Concerns::ResourceFinderTest < ActionController::TestCase
  tests DeviseTokenAuth::SessionsController

  describe DeviseTokenAuth::Concerns::ResourceFinder do
    describe '#provider' do
      it 'returns "email"' do
        assert_equal 'email', @controller.provider
      end
    end

    describe '#resource_class' do
      it 'returns User when called without arguments (default devise mapping)' do
        assert_equal User, @controller.resource_class
      end

      it 'returns the correct class for an explicit mapping argument' do
        assert_equal Mang, @controller.resource_class(:mang)
      end
    end

    if DEVISE_TOKEN_AUTH_ORM == :active_record
      describe '#database_adapter' do
        it 'returns a String identifying the configured database adapter' do
          assert_kind_of String, @controller.database_adapter
          refute_empty @controller.database_adapter
        end
      end

      describe '#find_resource' do
        describe 'standard user' do
          before do
            @existing_user = create(:user, :confirmed)
            post :create, params: { email: @existing_user.email,
                                    password: @existing_user.password }
          end

          it 'assigns the matching resource' do
            assert_equal @existing_user, assigns(:resource)
          end
        end

        describe 'non-existent email' do
          before do
            post :create, params: { email: 'nobody@example.com',
                                    password: 'wrongpassword' }
          end

          it 'returns 401' do
            assert_equal 401, response.status
          end

          it 'does not assign a resource' do
            assert_nil assigns(:resource)
          end
        end
      end
    else
      # Mongoid: connection_db_config is not available; database_adapter returns nil.
      describe '#database_adapter' do
        it 'returns nil for Mongoid (no SQL connection)' do
          assert_nil @controller.database_adapter
        end
      end
    end
  end
end

# Tests for the multi_email branch of find_resource require ActiveRecord and
# the /multi_email_auth routes.  They are placed in a separate integration test
# class to avoid forcing a route/mapping override on the unit tests above.
if DEVISE_TOKEN_AUTH_ORM == :active_record
  class DeviseTokenAuth::Concerns::ResourceFinderMultiEmailTest < ActionDispatch::IntegrationTest
    SIGN_IN_PASSWORD = 'secret123'

    describe 'ResourceFinder#find_resource with a multi_email user' do
      before do
        # Register and immediately confirm a MultiEmailUser.
        @email = Faker::Internet.unique.email
        post '/multi_email_auth',
             params: { email: @email, password: SIGN_IN_PASSWORD,
                       password_confirmation: SIGN_IN_PASSWORD,
                       confirm_success_url: Faker::Internet.url }
        assert_equal 200, response.status, "Setup failed: #{response.body}"
        @user = assigns(:resource)
        @user.confirm
      end

      it 'finds the multi_email user via the emails association' do
        post '/multi_email_auth/sign_in',
             params: { email: @email, password: SIGN_IN_PASSWORD }
        assert_equal 200, response.status
        assert_equal @user, assigns(:resource)
      end

      it 'returns 401 when email is unknown' do
        post '/multi_email_auth/sign_in',
             params: { email: 'nobody@example.com', password: SIGN_IN_PASSWORD }
        assert_equal 401, response.status
      end
    end
  end
end
