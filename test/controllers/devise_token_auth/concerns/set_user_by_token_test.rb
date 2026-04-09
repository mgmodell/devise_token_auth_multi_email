# frozen_string_literal: true

require 'test_helper'

# Tests targeting DeviseTokenAuth::Concerns::SetUserByToken behaviors that are
# not already covered by demo_user_controller_test.rb or
# token_validations_controller_test.rb.
#
# The DemoUserController at /demo/members_only is used as the test target
# because it runs set_user_by_token via the before_action inherited from
# ApplicationController (which includes SetUserByToken).
class DeviseTokenAuth::Concerns::SetUserByTokenTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  describe DeviseTokenAuth::Concerns::SetUserByToken do
    before do
      @resource = create(:user, :confirmed)
      @auth_headers = @resource.create_new_auth_token
      @token     = @auth_headers['access-token']
      @client_id = @auth_headers['client']
      @uid       = @auth_headers['uid']
    end

    # -------------------------------------------------------------------------
    # #set_request_start
    # -------------------------------------------------------------------------
    describe '#set_request_start' do
      before do
        age_token(@resource, @client_id)
        get '/demo/members_only', params: {}, headers: @auth_headers
      end

      it 'sets @request_started_at to the current time' do
        assert_kind_of Time, assigns(:request_started_at)
      end

      it 'initializes @resource' do
        refute_nil assigns(:resource)
      end

      it 'initializes @token' do
        refute_nil assigns(:token)
      end
    end

    # -------------------------------------------------------------------------
    # #set_user_by_token – authentication via query parameters
    # -------------------------------------------------------------------------
    describe 'token auth via query params' do
      before do
        age_token(@resource, @client_id)
        # Pass the three auth values as query-string parameters, not headers.
        get '/demo/members_only',
            params: {
              'access-token' => @token,
              'client'       => @client_id,
              'uid'          => @uid
            }
      end

      it 'returns 200' do
        assert_equal 200, response.status
      end

      it 'authenticates the correct user' do
        assert_equal @resource, assigns(:resource)
      end

      it 'returns a new access token in the response headers' do
        assert response.headers['access-token'].present?
      end
    end

    # -------------------------------------------------------------------------
    # #set_user_by_token – authentication via auth cookie
    # -------------------------------------------------------------------------
    describe 'token auth via auth cookie' do
      before do
        DeviseTokenAuth.cookie_enabled = true

        # Sign in to receive the auth cookie from the server.
        post '/auth/sign_in',
             params: { email: @resource.email, password: @resource.password }
        assert_equal 200, response.status, "Sign-in failed: #{response.body}"

        # The integration session retains the Set-Cookie from sign-in.
        # Make a protected request without explicit auth headers; the cookie
        # should carry the credentials for set_user_by_token to use.
        get '/demo/members_only', params: {}, headers: {}
      end

      after do
        DeviseTokenAuth.cookie_enabled = false
      end

      it 'returns 200' do
        assert_equal 200, response.status
      end

      it 'authenticates the correct user' do
        assert_equal @resource, assigns(:resource)
      end
    end

    # -------------------------------------------------------------------------
    # #decode_bearer_token – tested indirectly via /auth/validate_token
    # -------------------------------------------------------------------------
    describe '#decode_bearer_token' do
      before do
        age_token(@resource, @client_id)
      end

      describe 'with a blank Authorization header' do
        before do
          get '/auth/validate_token', params: {}, headers: {}
        end

        it 'returns 401 (no credentials provided)' do
          assert_equal 401, response.status
        end
      end

      describe 'with an invalid base64 Bearer token' do
        before do
          get '/auth/validate_token', params: {},
              headers: { 'Authorization' => 'Bearer not-valid-base64!!!' }
        end

        it 'returns 401 (decoded token treated as empty hash)' do
          assert_equal 401, response.status
        end
      end

      describe 'with valid base64 but non-JSON payload' do
        before do
          non_json_token = Base64.strict_encode64('this is not json')
          get '/auth/validate_token', params: {},
              headers: { 'Authorization' => "Bearer #{non_json_token}" }
        end

        it 'returns 401 (JSON parse error rescued to empty hash)' do
          assert_equal 401, response.status
        end
      end

      describe 'with a valid Bearer token (correct uid + access-token + client)' do
        before do
          encoded = Base64.strict_encode64(@auth_headers.to_json)
          get '/auth/validate_token', params: {},
              headers: { 'Authorization' => "Bearer #{encoded}" }
        end

        it 'returns 200' do
          assert_equal 200, response.status
        end

        it 'authenticates the correct user' do
          assert_equal @resource, assigns(:resource)
        end
      end
    end

    # -------------------------------------------------------------------------
    # #set_user_by_token – no credentials at all → resource is nil
    # -------------------------------------------------------------------------
    describe 'when no auth credentials are provided' do
      before do
        get '/demo/members_only', params: {}, headers: {}
      end

      it 'returns 401' do
        assert_equal 401, response.status
      end

      it 'does not authenticate a resource' do
        assert_nil assigns(:resource)
      end
    end

    # -------------------------------------------------------------------------
    # #update_auth_header – cookie updated on each request when cookie_enabled
    # -------------------------------------------------------------------------
    describe 'update_auth_header with cookie_enabled' do
      before do
        DeviseTokenAuth.cookie_enabled = true
        age_token(@resource, @client_id)
        get '/demo/members_only', params: {}, headers: @auth_headers
      end

      after do
        DeviseTokenAuth.cookie_enabled = false
      end

      it 'sets the auth cookie on the response' do
        assert response.cookies[DeviseTokenAuth.cookie_name].present?
      end
    end
  end
end
