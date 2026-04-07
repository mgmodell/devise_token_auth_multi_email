# frozen_string_literal: true

require 'test_helper'

# Tests that verify devise_token_auth works correctly with a **standard** model —
# one that does NOT use devise-multi_email (i.e. does NOT have multi_email_association).
#
# Standard models get the email uniqueness validation directly from
# DeviseTokenAuth::Concerns::UserOmniauthCallbacks, regardless of whether the
# devise-multi_email gem is loaded. These tests confirm:
#   • Basic registration, authentication, and account management work.
#   • Duplicate email registrations are rejected at the model level (no DB
#     constraint exception reaching PostgreSQL that would abort the transaction).
#   • An OAuth user's email can be re-used for an email-provider registration
#     because uniqueness is scoped to provider.
#
# These tests are ActiveRecord-specific because they validate AR-level validators
# and the MultiEmailUser ActiveRecord model (used for contrast tests).
return unless DEVISE_TOKEN_AUTH_ORM == :active_record

class StandardUserRegistrationsControllerTest < ActionDispatch::IntegrationTest
  describe 'Standard User (without multi_email_authenticatable)' do
    def registration_params(email: nil)
      {
        email:                 email || Faker::Internet.unique.email,
        password:              'secret123',
        password_confirmation: 'secret123',
        confirm_success_url:   Faker::Internet.url
      }
    end

    # -----------------------------------------------------------------------
    # Uniqueness validation lives in the concern for standard models
    # -----------------------------------------------------------------------
    describe 'email uniqueness' do
      test 'validates uniqueness at the model level — not at the DB' do
        # The concern (UserOmniauthCallbacks) adds this validation for standard
        # models so the check happens before the INSERT, keeping PostgreSQL
        # transactions clean.
        assert User.validators_on(:email).any? { |v|
          v.is_a?(ActiveRecord::Validations::UniquenessValidator)
        }, 'Expected a UniquenessValidator on User#email'

        assert Mang.validators_on(:email).any? { |v|
          v.is_a?(ActiveRecord::Validations::UniquenessValidator)
        }, 'Expected a UniquenessValidator on Mang#email'
      end

      test 'multi_email model does NOT carry the concern uniqueness validator' do
        # MultiEmailUser uses :multi_email_authenticatable so it has
        # multi_email_association — the concern skips adding the uniqueness
        # validator (the emails table enforces uniqueness instead).
        refute MultiEmailUser.validators_on(:email).any? { |v|
          v.is_a?(ActiveRecord::Validations::UniquenessValidator)
        }, 'Expected NO UniquenessValidator on MultiEmailUser#email'
      end
    end

    # -----------------------------------------------------------------------
    # Successful registration
    # -----------------------------------------------------------------------
    describe 'successful registration' do
      before do
        post '/auth', params: registration_params
        @resource = assigns(:resource)
        @data = JSON.parse(response.body)
      end

      test 'request is successful' do
        assert_equal 200, response.status
      end

      test 'user is persisted' do
        assert @resource.id
      end

      test 'resource is a standard User' do
        assert_equal User, @resource.class
      end

      test 'response includes email' do
        assert @data['data']['email']
      end
    end

    # -----------------------------------------------------------------------
    # Duplicate email registration is rejected at the model level
    # -----------------------------------------------------------------------
    describe 'duplicate email registration' do
      before do
        @email = Faker::Internet.unique.email
        create(:user, email: @email, provider: 'email').tap(&:confirm)

        post '/auth', params: registration_params(email: @email)
        @data = JSON.parse(response.body)
      end

      test 'request is rejected' do
        assert_equal 422, response.status
      end

      test 'errors mention email taken' do
        assert_not_empty @data['errors']
      end
    end

    # -----------------------------------------------------------------------
    # OAuth user + same email re-used for email-provider registration
    # (uniqueness is scoped to provider)
    # -----------------------------------------------------------------------
    describe 'email re-use across providers' do
      before do
        @oauth_user = create(:user, :facebook, :confirmed)

        post '/auth',
             params: registration_params(email: @oauth_user.email)

        @resource = assigns(:resource)
        @data = JSON.parse(response.body)
      end

      test 'registration is successful' do
        assert_equal 200, response.status
      end

      test 'a new email-provider user is created' do
        assert @resource.id
        assert_equal 'email', @resource.provider
      end
    end

    # -----------------------------------------------------------------------
    # Mang (another standard model, at /mangs)
    # -----------------------------------------------------------------------
    describe 'alternate standard model (Mang)' do
      before do
        post '/mangs', params: registration_params
        @resource = assigns(:resource)
        @data = JSON.parse(response.body)
      end

      test 'registration is successful' do
        assert_equal 200, response.status
      end

      test 'resource is a Mang' do
        assert_equal Mang, @resource.class
      end
    end

    describe 'Mang duplicate email is rejected at model level' do
      before do
        @email = Faker::Internet.unique.email
        create(:mang_user, email: @email, provider: 'email').tap(&:confirm)

        post '/mangs', params: registration_params(email: @email)
        @data = JSON.parse(response.body)
      end

      test 'request is rejected' do
        assert_equal 422, response.status
      end
    end
  end
end
