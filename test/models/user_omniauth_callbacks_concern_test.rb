# frozen_string_literal: true

require 'test_helper'

# Unit tests for DeviseTokenAuth::Concerns::UserOmniauthCallbacks.
#
# The concern is included in every model that includes
# DeviseTokenAuth::Concerns::User.  It is responsible for:
#   - Keeping uid in sync with email for email-provider users (sync_uid).
#   - Validating uid presence for OAuth providers.
#   - Providing the email_provider? and uid_and_provider_defined? helpers.
class UserOmniauthCallbacksConcernTest < ActiveSupport::TestCase
  describe DeviseTokenAuth::Concerns::UserOmniauthCallbacks do
    # -------------------------------------------------------------------------
    # #uid_and_provider_defined?
    # -------------------------------------------------------------------------
    describe '#uid_and_provider_defined?' do
      test 'returns true for User (which has provider and uid columns)' do
        resource = User.new
        assert resource.send(:uid_and_provider_defined?)
      end

      if DEVISE_TOKEN_AUTH_ORM == :active_record
        test 'returns true for MultiEmailUser' do
          resource = MultiEmailUser.new
          assert resource.send(:uid_and_provider_defined?)
        end
      end
    end

    # -------------------------------------------------------------------------
    # #email_provider?
    # -------------------------------------------------------------------------
    describe '#email_provider?' do
      test 'returns true when provider is "email"' do
        resource = User.new(provider: 'email')
        assert resource.send(:email_provider?)
      end

      test 'returns false when provider is not "email"' do
        resource = User.new(provider: 'facebook')
        refute resource.send(:email_provider?)
      end

      test 'returns false when provider is nil' do
        resource = User.new(provider: nil)
        refute resource.send(:email_provider?)
      end
    end

    # -------------------------------------------------------------------------
    # sync_uid (via before_save / before_create callbacks)
    # -------------------------------------------------------------------------
    describe 'sync_uid' do
      if DEVISE_TOKEN_AUTH_ORM == :active_record
        describe 'email-provider user' do
          test 'uid is set to email when creating a new email-provider user' do
            email = Faker::Internet.unique.email
            resource = create(:user, email: email, provider: 'email')
            assert_equal email, resource.uid,
                         'uid should be synced from email on creation'
          end

          test 'uid is updated when email changes on an existing user' do
            resource = create(:user, :confirmed)
            new_email = Faker::Internet.unique.email
            resource.email = new_email
            resource.save(validate: false)
            assert_equal new_email, resource.uid,
                         'uid should stay in sync with email after update'
          end
        end

        describe 'OAuth provider user' do
          test 'uid is NOT overwritten with email for non-email providers' do
            uid = '12345'
            resource = build(:user, :facebook, uid: uid)
            resource.save(validate: false)
            assert_equal uid, resource.uid,
                         'uid should remain unchanged for OAuth providers'
          end
        end
      end
    end

    # -------------------------------------------------------------------------
    # Validation: email presence (email provider)
    # -------------------------------------------------------------------------
    describe 'email presence validation' do
      if DEVISE_TOKEN_AUTH_ORM == :active_record
        test 'fails to save email-provider user without email' do
          resource = User.new(provider: 'email', uid: '', password: 'secret123',
                              password_confirmation: 'secret123')
          refute resource.save
          assert resource.errors[:email].any?
        end

        test 'saves OAuth user without email' do
          resource = User.new(provider: 'facebook', uid: '999', email: nil)
          # skip uniqueness / other validations to test only email presence
          resource.password = resource.password_confirmation = 'secret123'
          result = resource.save(validate: false)
          assert result
        end
      end
    end

    # -------------------------------------------------------------------------
    # Validation: uid presence (OAuth provider)
    # -------------------------------------------------------------------------
    describe 'uid presence validation for OAuth users' do
      if DEVISE_TOKEN_AUTH_ORM == :active_record
        test 'fails to save OAuth user without uid' do
          resource = User.new(provider: 'facebook', uid: nil)
          resource.password = resource.password_confirmation = 'secret123'
          resource.save
          assert resource.errors[:uid].any?,
                 'Expected a validation error on :uid for OAuth users with nil uid'
        end
      end
    end
  end
end
