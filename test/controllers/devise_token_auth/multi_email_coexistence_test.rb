# frozen_string_literal: true

require 'test_helper'

# Tests that verify standard models and multi-email models can coexist in the
# same Rails application without interfering with each other.
#
# Specifically:
#   • Standard (User, Mang) and multi-email (MultiEmailUser) routes all work.
#   • The same email address can be used across different model types (they
#     live in different tables so there is no cross-model constraint conflict).
#   • Token authentication works independently for each model type.
#   • Session isolation: signing in on one model doesn't affect another.
class MultiEmailCoexistenceTest < ActionDispatch::IntegrationTest
  def standard_params(email: nil)
    {
      email:                 email || Faker::Internet.unique.email,
      password:              'secret123',
      password_confirmation: 'secret123',
      confirm_success_url:   Faker::Internet.url
    }
  end
  alias multi_email_params standard_params

  # -------------------------------------------------------------------------
  # Both model types can register simultaneously
  # -------------------------------------------------------------------------
  describe 'independent registration' do
    test 'standard user can register at /auth' do
      post '/auth', params: standard_params
      assert_equal 200, response.status
      assert_equal 'User', assigns(:resource).class.name
    end

    test 'multi-email user can register at /multi_email_auth' do
      post '/multi_email_auth', params: multi_email_params
      assert_equal 200, response.status
      assert_equal 'MultiEmailUser', assigns(:resource).class.name
    end

    test 'mang (another standard model) can register at /mangs' do
      post '/mangs', params: standard_params
      assert_equal 200, response.status
      assert_equal 'Mang', assigns(:resource).class.name
    end
  end

  # -------------------------------------------------------------------------
  # Same email address may exist in both the users table and the
  # multi_email_user_emails table simultaneously (different tables / models)
  # -------------------------------------------------------------------------
  describe 'same email across different models' do
    before do
      @shared_email = Faker::Internet.unique.email
    end

    test 'standard user and multi-email user can share an email address' do
      # Register a standard User with the email
      post '/auth', params: standard_params(email: @shared_email)
      assert_equal 200, response.status,
                   "Standard user registration failed: #{response.body}"

      # Register a MultiEmailUser with the same email — succeeds because the
      # models live in separate tables with no cross-table uniqueness constraint.
      post '/multi_email_auth', params: multi_email_params(email: @shared_email)
      assert_equal 200, response.status,
                   "MultiEmailUser registration with shared email failed: #{response.body}"
    end
  end

  # -------------------------------------------------------------------------
  # Each model has its own independent token authentication
  # -------------------------------------------------------------------------
  describe 'independent token authentication' do
    before do
      @std_user = create(:user, :confirmed)
      @me_user  = create(:multi_email_user, email: Faker::Internet.unique.email,
                          provider: 'email')
      @me_user.confirm

      # Sign in both users
      post '/auth/sign_in',
           params: { email: @std_user.email, password: @std_user.password }
      @std_headers = {
        'access-token' => response.headers['access-token'],
        'client'       => response.headers['client'],
        'uid'          => response.headers['uid']
      }

      post '/multi_email_auth/sign_in',
           params: { email: @me_user.email, password: @me_user.password }
      @me_headers = {
        'access-token' => response.headers['access-token'],
        'client'       => response.headers['client'],
        'uid'          => response.headers['uid']
      }
    end

    test 'standard user token validates at /auth/validate_token' do
      get '/auth/validate_token', headers: @std_headers
      assert_equal 200, response.status
    end

    test 'multi-email user token validates at /multi_email_auth/validate_token' do
      get '/multi_email_auth/validate_token', headers: @me_headers
      assert_equal 200, response.status
    end

    test 'standard user token is NOT valid at multi-email endpoint' do
      get '/multi_email_auth/validate_token', headers: @std_headers
      assert_includes [401, 404], response.status
    end

    test 'multi-email user token is NOT valid at standard endpoint' do
      get '/auth/validate_token', headers: @me_headers
      assert_includes [401, 404], response.status
    end
  end

  # -------------------------------------------------------------------------
  # Models do not share validation state
  # -------------------------------------------------------------------------
  describe 'independent validation' do
    test 'duplicate standard user email is rejected at model level' do
      email = Faker::Internet.unique.email
      create(:user, email: email, provider: 'email').confirm

      post '/auth', params: standard_params(email: email)
      assert_equal 422, response.status
    end

    test 'duplicate multi-email user email is rejected' do
      email = Faker::Internet.unique.email
      existing = create(:multi_email_user, email: email, provider: 'email')
      existing.confirm

      post '/multi_email_auth', params: multi_email_params(email: email)
      assert_equal 422, response.status
    end
  end
end
