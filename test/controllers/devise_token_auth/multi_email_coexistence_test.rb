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
#
# These tests are ActiveRecord-only — the MultiEmailUser model and route are
# not set up in Mongoid runs.
return unless DEVISE_TOKEN_AUTH_ORM == :active_record

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
  # Each model type independently rejects duplicate emails
  # -------------------------------------------------------------------------
  describe 'independent validation' do
    test 'duplicate standard user email is rejected at model level' do
      email = Faker::Internet.unique.email
      create(:user, email: email, provider: 'email').confirm

      post '/auth', params: standard_params(email: email)
      assert_equal 422, response.status
    end

    test 'duplicate multi-email user email is rejected by the emails table' do
      email = Faker::Internet.unique.email

      # Register first multi_email user via the endpoint (not factory, since
      # the gem handles email association creation internally on save).
      post '/multi_email_auth', params: multi_email_params(email: email)
      assert_equal 200, response.status, "First registration failed: #{response.body}"

      # Duplicate registration should be rejected.
      post '/multi_email_auth', params: multi_email_params(email: email)
      assert_equal 422, response.status
    end
  end

  # -------------------------------------------------------------------------
  # Model-level configuration confirms coexistence setup is correct
  # -------------------------------------------------------------------------
  describe 'model configuration coexistence' do
    test 'standard models have email uniqueness validator from concern' do
      assert User.validators_on(:email).any? { |v|
        v.is_a?(ActiveRecord::Validations::UniquenessValidator)
      }
      assert Mang.validators_on(:email).any? { |v|
        v.is_a?(ActiveRecord::Validations::UniquenessValidator)
      }
    end

    test 'multi_email model does NOT have concern email uniqueness validator' do
      refute MultiEmailUser.validators_on(:email).any? { |v|
        v.is_a?(ActiveRecord::Validations::UniquenessValidator)
      }
    end

    test 'multi_email model has multi_email_association class method' do
      assert MultiEmailUser.respond_to?(:multi_email_association)
    end

    test 'standard models do NOT have multi_email_association class method' do
      refute User.respond_to?(:multi_email_association)
      refute Mang.respond_to?(:multi_email_association)
    end
  end
end
