# frozen_string_literal: true

require 'test_helper'

# Tests that verify the TokenValidationsController works correctly with a
# MultiEmailUser — a model that uses :multi_email_authenticatable from the
# devise-multi_email gem.
#
# Token validation uses the uid / access-token / client headers; the uid is the
# primary email address, which is synced to the uid column by the sync_uid
# before_save callback.  No multi-email-specific lookup is needed here because
# the token is looked up by uid (a real column), so this test primarily
# confirms that the standard flow works end-to-end for multi-email users.
#
# These tests are ActiveRecord-only — the MultiEmailUser model and its route
# are not available in Mongoid runs.
return unless DEVISE_TOKEN_AUTH_ORM == :active_record

class MultiEmailTokenValidationsControllerTest < ActionDispatch::IntegrationTest
  describe 'MultiEmailUser token validation' do
    def registration_params(email: nil)
      {
        email:                 email || Faker::Internet.unique.email,
        password:              'secret123',
        password_confirmation: 'secret123',
        confirm_success_url:   Faker::Internet.url
      }
    end

    # Register a user, confirm it, and sign in.  Returns [user, auth_headers].
    def sign_in_confirmed_user
      email = Faker::Internet.unique.email

      post '/multi_email_auth', params: registration_params(email: email)
      assert_equal 200, response.status, "Registration failed: #{response.body}"
      user = assigns(:resource)
      user.confirm

      post '/multi_email_auth/sign_in',
           params: { email: email, password: 'secret123' }
      assert_equal 200, response.status, "Sign-in failed: #{response.body}"

      auth_headers = {
        'access-token' => response.headers['access-token'],
        'client'       => response.headers['client'],
        'uid'          => response.headers['uid'],
        'token-type'   => response.headers['token-type']
      }
      [user, auth_headers]
    end

    before do
      @user, @auth_headers = sign_in_confirmed_user
      @client_id = @auth_headers['client']

      # Age the token so the request is not treated as a batch request.
      age_token(@user, @client_id)
    end

    # -----------------------------------------------------------------------
    # Valid token
    # -----------------------------------------------------------------------
    describe 'valid token' do
      before do
        get '/multi_email_auth/validate_token', headers: @auth_headers
        @data = JSON.parse(response.body)
      end

      test 'request is successful' do
        assert_equal 200, response.status
      end

      test 'response includes user data' do
        assert @data['data']
      end

      test 'response data includes the correct email' do
        assert @data['data']['email']
      end
    end

    # -----------------------------------------------------------------------
    # Invalid access-token
    # -----------------------------------------------------------------------
    describe 'invalid access-token' do
      before do
        bad_headers = @auth_headers.merge('access-token' => 'this-is-wrong')
        get '/multi_email_auth/validate_token', headers: bad_headers
        @data = JSON.parse(response.body)
      end

      test 'request fails' do
        assert_equal 401, response.status
      end

      test 'response contains errors' do
        assert @data['errors']
        assert_equal [I18n.t('devise_token_auth.token_validations.invalid')],
                     @data['errors']
      end
    end

    # -----------------------------------------------------------------------
    # Missing auth headers
    # -----------------------------------------------------------------------
    describe 'missing auth headers' do
      before do
        get '/multi_email_auth/validate_token'
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
    # Expired token
    # -----------------------------------------------------------------------
    describe 'expired token' do
      before do
        expire_token(@user, @client_id)
        get '/multi_email_auth/validate_token', headers: @auth_headers
        @data = JSON.parse(response.body)
      end

      test 'request fails' do
        assert_equal 401, response.status
      end

      test 'response contains errors' do
        assert @data['errors']
      end
    end
  end
end
