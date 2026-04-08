# frozen_string_literal: true

require 'test_helper'

# Tests that verify the SessionsController works correctly with a MultiEmailUser —
# a model that uses :multi_email_authenticatable from the devise-multi_email gem.
#
# Authentication for multi-email users goes through MultiEmailUserEmail records
# rather than a direct email column.  The ResourceFinder concern detects the
# multi_email_association class method and delegates to find_by_email so that
# sign-in lookups correctly traverse the emails association.
#
# These tests are ActiveRecord-only — the MultiEmailUser model and its route
# are not available in Mongoid runs.
return unless DEVISE_TOKEN_AUTH_ORM == :active_record

class MultiEmailSessionsControllerTest < ActionDispatch::IntegrationTest
  SIGN_IN_PASSWORD = 'secret123'

  describe 'MultiEmailUser sessions' do
    def registration_params(email: nil)
      {
        email:                 email || Faker::Internet.unique.email,
        password:              SIGN_IN_PASSWORD,
        password_confirmation: SIGN_IN_PASSWORD,
        confirm_success_url:   Faker::Internet.url
      }
    end

    # Create a confirmed MultiEmailUser by registering through the endpoint and
    # then calling confirm on the resource so the account is immediately active.
    def create_confirmed_user(email: nil)
      email ||= Faker::Internet.unique.email
      post '/multi_email_auth', params: registration_params(email: email)
      assert_equal 200, response.status, "Setup registration failed: #{response.body}"
      user = assigns(:resource)
      user.confirm
      [user, email]
    end

    # -----------------------------------------------------------------------
    # Sign in — confirmed user
    # -----------------------------------------------------------------------
    describe 'sign in with confirmed user' do
      before do
        @user, @email = create_confirmed_user
        post '/multi_email_auth/sign_in',
             params: { email: @email, password: SIGN_IN_PASSWORD }
        @data = JSON.parse(response.body)
      end

      test 'request is successful' do
        assert_equal 200, response.status
      end

      test 'response includes user data' do
        assert @data['data']
        assert_equal @email, @data['data']['email']
      end

      test 'response includes access-token header' do
        assert response.headers['access-token']
      end

      test 'response includes client header' do
        assert response.headers['client']
      end

      test 'response includes uid header' do
        assert response.headers['uid']
      end
    end

    # -----------------------------------------------------------------------
    # Sign in — wrong password
    # -----------------------------------------------------------------------
    describe 'sign in with wrong password' do
      before do
        @user, @email = create_confirmed_user
        post '/multi_email_auth/sign_in',
             params: { email: @email, password: 'definitely-wrong' }
        @data = JSON.parse(response.body)
      end

      test 'request fails' do
        assert_equal 401, response.status
      end

      test 'response contains errors' do
        assert @data['errors']
        assert_equal [I18n.t('devise_token_auth.sessions.bad_credentials')],
                     @data['errors']
      end
    end

    # -----------------------------------------------------------------------
    # Sign in — unconfirmed user
    # -----------------------------------------------------------------------
    describe 'sign in with unconfirmed user' do
      before do
        @email = Faker::Internet.unique.email
        post '/multi_email_auth', params: registration_params(email: @email)
        assert_equal 200, response.status, "Setup registration failed: #{response.body}"
        # Do NOT confirm the user.
        post '/multi_email_auth/sign_in',
             params: { email: @email, password: SIGN_IN_PASSWORD }
        @data = JSON.parse(response.body)
      end

      test 'request fails' do
        assert_equal 401, response.status
      end

      test 'response contains errors' do
        assert @data['errors']
      end
    end

    # -----------------------------------------------------------------------
    # Sign in — non-existent email
    # -----------------------------------------------------------------------
    describe 'sign in with non-existent email' do
      before do
        post '/multi_email_auth/sign_in',
             params: { email: Faker::Internet.unique.email, password: SIGN_IN_PASSWORD }
        @data = JSON.parse(response.body)
      end

      test 'request fails' do
        assert_equal 401, response.status
      end

      test 'response contains errors' do
        assert @data['errors']
      end
    end

    # -----------------------------------------------------------------------
    # Sign out — authenticated user
    # -----------------------------------------------------------------------
    describe 'sign out authenticated user' do
      before do
        @user, @email = create_confirmed_user

        post '/multi_email_auth/sign_in',
             params: { email: @email, password: SIGN_IN_PASSWORD }
        assert_equal 200, response.status, "Sign-in failed: #{response.body}"

        @auth_headers = {
          'access-token' => response.headers['access-token'],
          'client'       => response.headers['client'],
          'uid'          => response.headers['uid'],
          'token-type'   => response.headers['token-type']
        }
        @client_id = @auth_headers['client']

        delete '/multi_email_auth/sign_out', headers: @auth_headers
        @data = JSON.parse(response.body)
      end

      test 'sign out is successful' do
        assert_equal 200, response.status
      end

      test 'token is invalidated' do
        @user.reload
        assert_nil @user.tokens[@client_id]
      end
    end

    # -----------------------------------------------------------------------
    # Sign out — unauthenticated user
    # -----------------------------------------------------------------------
    describe 'sign out without authentication' do
      before do
        delete '/multi_email_auth/sign_out'
        @data = JSON.parse(response.body)
      end

      test 'request fails with 404' do
        assert_equal 404, response.status
      end

      test 'response contains errors' do
        assert @data['errors']
        assert_equal [I18n.t('devise_token_auth.sessions.user_not_found')],
                     @data['errors']
      end
    end
  end
end
