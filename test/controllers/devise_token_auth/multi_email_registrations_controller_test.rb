# frozen_string_literal: true

require 'test_helper'

# Tests that verify devise_token_auth works correctly with a **multi-email**
# model — one that includes Devise::MultiEmail::ParentModelConcern.
#
# With multi_email active on a model:
#   • Email uniqueness is managed through the emails association/table, NOT by
#     a column-level validation on the model itself.
#   • After registration, an email record exists in multi_email_user_emails.
#   • The user's primary email is accessible via the emails association.
#   • Duplicate email registration is still rejected (enforced by the emails
#     table unique index and Devise::MultiEmail's own validation).
class MultiEmailRegistrationsControllerTest < ActionDispatch::IntegrationTest
  describe 'MultiEmailUser (with Devise::MultiEmail::ParentModelConcern)' do
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
      test 'MultiEmailUser includes Devise::MultiEmail::ParentModelConcern' do
        assert MultiEmailUser.ancestors.include?(Devise::MultiEmail::ParentModelConcern)
      end

      test 'MultiEmailUser has the emails association' do
        assert MultiEmailUser.reflect_on_association(:emails)
      end

      test 'MultiEmailUserEmail includes Devise::MultiEmail::EmailModelConcern' do
        assert MultiEmailUserEmail.ancestors.include?(Devise::MultiEmail::EmailModelConcern)
      end

      test 'MultiEmailUser does NOT carry the concern uniqueness validator' do
        # email uniqueness is handled by the emails table, not the user model
        refute MultiEmailUser.validators_on(:email).any? { |v|
          v.is_a?(ActiveRecord::Validations::UniquenessValidator)
        }
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
        assert email_record.primary_email_record
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
        existing = create(:multi_email_user, email: @email, provider: 'email')
        existing.confirm

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
    # Sign-in after registration
    # -----------------------------------------------------------------------
    describe 'sign-in after registration' do
      before do
        @email = Faker::Internet.unique.email
        @password = 'secret123'

        post '/multi_email_auth',
             params: registration_params(email: @email).merge(password: @password,
                                                               password_confirmation: @password)
        @resource = assigns(:resource)
        @resource.confirm

        post '/multi_email_auth/sign_in',
             params: { email: @email, password: @password }
        @data = JSON.parse(response.body)
      end

      test 'sign-in is successful' do
        assert_equal 200, response.status
      end

      test 'response returns user data' do
        assert @data['data']['email']
      end
    end
  end
end
