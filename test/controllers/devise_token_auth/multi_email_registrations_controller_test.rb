# frozen_string_literal: true

require 'test_helper'

# Tests that verify devise_token_auth works correctly with a **multi-email**
# model — one that uses :multi_email_authenticatable from the devise-multi_email gem.
#
# With multi_email active on a model:
#   • Email uniqueness is managed through the emails association/table, NOT by
#     a column-level validation on the model itself.
#   • After registration, an email record exists in multi_email_user_emails.
#   • The user's primary email is accessible via the emails association.
#   • Duplicate email registration is still rejected (enforced by the emails
#     table unique index and Devise::MultiEmail's own validation).
#
# These tests are ActiveRecord-only — the MultiEmailUser model and its
# devise-multi_email setup are not available in Mongoid runs.
return unless DEVISE_TOKEN_AUTH_ORM == :active_record

class MultiEmailRegistrationsControllerTest < ActionDispatch::IntegrationTest
  describe 'MultiEmailUser (with :multi_email_authenticatable)' do
    def registration_params(email: nil)
      {
        email:                 email || Faker::Internet.unique.email,
        password:              'secret123',
        password_confirmation: 'secret123',
        confirm_success_url:   Faker::Internet.url
      }
    end

    # -----------------------------------------------------------------------
    # Model configuration sanity checks
    # -----------------------------------------------------------------------
    describe 'model configuration' do
      test 'MultiEmailUser has multi_email_association class method' do
        # Added by Devise::MultiEmail::ParentModelExtensions via :multi_email_authenticatable
        assert MultiEmailUser.respond_to?(:multi_email_association)
      end

      test 'MultiEmailUser has the emails association' do
        assert MultiEmailUser.reflect_on_association(:emails)
      end

      test 'MultiEmailUser has find_by_email class method' do
        # Added by Devise::Models::MultiEmailAuthenticatable::ClassMethods
        assert MultiEmailUser.respond_to?(:find_by_email)
      end

      test 'MultiEmailUser does NOT carry the concern uniqueness validator' do
        # email uniqueness is handled by the emails table, not the user model
        refute MultiEmailUser.validators_on(:email).any? { |v|
          v.is_a?(ActiveRecord::Validations::UniquenessValidator)
        }
      end

      test 'MultiEmailUserEmail has email uniqueness validator from EmailValidatable' do
        # Devise::Models::EmailValidatable is included into MultiEmailUserEmail
        # automatically by MultiEmailUser's ParentModelExtensions when the
        # :multi_email_validatable module is set up.
        #
        # Ensure MultiEmailUser is loaded to trigger the association setup:
        MultiEmailUser

        assert MultiEmailUserEmail.validators_on(:email).any? { |v|
          v.is_a?(ActiveRecord::Validations::UniquenessValidator)
        }, 'Expected UniquenessValidator on MultiEmailUserEmail#email (from EmailValidatable)'
      end
    end

    # -----------------------------------------------------------------------
    # Successful registration
    # -----------------------------------------------------------------------
    describe 'successful registration' do
      before do
        @email = Faker::Internet.unique.email
        post '/multi_email_auth', params: registration_params(email: @email)
        @resource = assigns(:resource)
        @data = JSON.parse(response.body)
      end

      test 'request is successful' do
        assert_equal 200, response.status
      end

      test 'resource is a MultiEmailUser' do
        assert_equal MultiEmailUser, @resource.class
      end

      test 'user is persisted' do
        assert @resource.id
      end

      test 'response includes email' do
        assert @data['data']['email']
      end

      test 'an email record is created in the emails association' do
        assert_equal 1, @resource.emails.count
      end

      test 'primary email record is marked correctly' do
        email_record = @resource.emails.first
        assert email_record.primary?
      end

      test 'the email record stores the registered email' do
        assert_equal @email, @resource.emails.first.email
      end
    end

    # -----------------------------------------------------------------------
    # Duplicate email registration is rejected
    # -----------------------------------------------------------------------
    describe 'duplicate email registration' do
      before do
        @email = Faker::Internet.unique.email

        # Register the first user via the endpoint (not factory), since
        # the gem handles email association creation on save internally.
        post '/multi_email_auth', params: registration_params(email: @email)
        assert_equal 200, response.status, "Setup registration failed: #{response.body}"

        # Attempt a duplicate registration
        post '/multi_email_auth', params: registration_params(email: @email)
        @data = JSON.parse(response.body)
      end

      test 'request is rejected' do
        assert_equal 422, response.status
      end

      test 'errors are returned' do
        assert_not_empty @data['errors']
      end
    end

    # -----------------------------------------------------------------------
    # Shared helper: register, confirm, and sign in a MultiEmailUser.
    # Returns [user, auth_headers].
    # -----------------------------------------------------------------------
    def sign_in_confirmed_user(email: nil)
      email ||= Faker::Internet.unique.email
      post '/multi_email_auth', params: registration_params(email: email)
      assert_equal 200, response.status, "Setup registration failed: #{response.body}"
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

    # -----------------------------------------------------------------------
    # Update account (PUT /multi_email_auth)
    # -----------------------------------------------------------------------
    describe 'account update' do
      describe 'successful account update (name field)' do
        before do
          @user, @auth_headers = sign_in_confirmed_user
          age_token(@user, @auth_headers['client'])

          put '/multi_email_auth',
              params: { name: 'Updated Name' },
              headers: @auth_headers
          @data = JSON.parse(response.body)
        end

        test 'request is successful' do
          assert_equal 200, response.status
        end

        test 'response status is success' do
          assert_equal 'success', @data['status']
        end

        test 'updated name is reflected in the response' do
          assert_equal 'Updated Name', @data['data']['name']
        end

        test 'name is persisted to the database' do
          @user.reload
          assert_equal 'Updated Name', @user.name
        end
      end

      describe 'account update without authentication' do
        before do
          put '/multi_email_auth',
              params: { name: 'Unauthenticated Update' }
          @data = JSON.parse(response.body)
        end

        test 'request fails with 404' do
          assert_equal 404, response.status
        end

        test 'user not found error is returned' do
          assert @data['errors']
        end
      end

      describe 'account update with empty body' do
        before do
          @user, @auth_headers = sign_in_confirmed_user
          age_token(@user, @auth_headers['client'])

          put '/multi_email_auth',
              params: {},
              headers: @auth_headers
          @data = JSON.parse(response.body)
        end

        test 'request fails with 422' do
          assert_equal 422, response.status
        end
      end
    end

    # -----------------------------------------------------------------------
    # Destroy account (DELETE /multi_email_auth)
    # -----------------------------------------------------------------------
    describe 'account destroy' do
      describe 'successful account deletion' do
        before do
          @user, @auth_headers = sign_in_confirmed_user
          @user_id = @user.id
          age_token(@user, @auth_headers['client'])

          delete '/multi_email_auth', headers: @auth_headers
          @data = JSON.parse(response.body)
        end

        test 'request is successful' do
          assert_equal 200, response.status
        end

        test 'success status is returned' do
          assert_equal 'success', @data['status']
        end

        test 'user is removed from the database' do
          refute MultiEmailUser.where(id: @user_id).exists?,
                 'MultiEmailUser should be deleted after destroy'
        end

        test 'associated email records are also deleted (dependent: :destroy)' do
          refute MultiEmailUserEmail.where(multi_email_user_id: @user_id).exists?,
                 'Email records should be destroyed with the user'
        end
      end

      describe 'account deletion without authentication' do
        before do
          delete '/multi_email_auth'
          @data = JSON.parse(response.body)
        end

        test 'request fails with 404' do
          assert_equal 404, response.status
        end

        test 'error message is returned' do
          assert @data['errors']
          assert @data['errors'].include?(
            I18n.t('devise_token_auth.registrations.account_to_destroy_not_found')
          )
        end
      end
    end
  end
end
