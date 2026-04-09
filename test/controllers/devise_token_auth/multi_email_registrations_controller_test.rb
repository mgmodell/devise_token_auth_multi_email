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

      test 'concern uniqueness validator never fires for MultiEmailUser' do
        # The concern adds a uniqueness validator with a runtime :if guard that
        # skips it whenever the model responds to :multi_email_association.
        # This ensures the validator is never exercised on multi-email models
        # (which have no email column and would otherwise crash on MySQL via
        # nil.case_sensitive?).
        #
        # The :if lambda is called via instance_exec on the record (arity 0),
        # so self inside the lambda is the user instance.
        user = MultiEmailUser.new(provider: 'email', uid: 'test@example.com')
        MultiEmailUser.validators_on(:email).select { |v|
          v.is_a?(ActiveRecord::Validations::UniquenessValidator) &&
            Array(v.options[:scope]).include?(:provider)
        }.each do |validator|
          if_procs = Array(validator.options[:if]).select { |c| c.respond_to?(:call) }
          refute if_procs.empty?,
                 'DTA concern uniqueness validator must have a runtime :if guard'
          assert if_procs.none? { |c| user.instance_exec(&c) },
                 'DTA concern uniqueness validator should not fire for multi-email models'
        end
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
  end
end
