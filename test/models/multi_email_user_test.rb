# frozen_string_literal: true

require 'test_helper'

# Tests for the MultiEmailUser model — the AR model that uses devise-multi_email
# alongside DeviseTokenAuth.  These tests are ActiveRecord-only because
# MultiEmailUser and its email association table are not available in Mongoid
# runs.
return unless DEVISE_TOKEN_AUTH_ORM == :active_record

class MultiEmailUserTest < ActiveSupport::TestCase
  describe MultiEmailUser do
    # -------------------------------------------------------------------------
    # Model configuration
    # -------------------------------------------------------------------------
    describe 'model configuration' do
      test 'has multi_email_association class method (added by :multi_email_authenticatable)' do
        assert MultiEmailUser.respond_to?(:multi_email_association)
      end

      test 'has emails has_many association' do
        assert MultiEmailUser.reflect_on_association(:emails),
               'Expected MultiEmailUser to have an :emails association'
      end

      test 'has find_by_email class method (added by MultiEmailAuthenticatable::ClassMethods)' do
        assert MultiEmailUser.respond_to?(:find_by_email)
      end

      test 'does NOT carry a column-level email uniqueness validator' do
        # email uniqueness is managed by the emails association table, not the
        # user model itself
        refute MultiEmailUser.validators_on(:email).any? { |v|
          v.is_a?(ActiveRecord::Validations::UniquenessValidator)
        }, 'MultiEmailUser should NOT have an email UniquenessValidator on the model'
      end

      test 'includes DeviseTokenAuth::Concerns::User' do
        assert MultiEmailUser.ancestors.include?(DeviseTokenAuth::Concerns::User)
      end

      test 'has devise module multi_email_authenticatable' do
        assert MultiEmailUser.devise_modules.include?(:multi_email_authenticatable)
      end
    end

    # -------------------------------------------------------------------------
    # Serialization
    # -------------------------------------------------------------------------
    describe 'serialization' do
      test 'tokens are not exposed in as_json' do
        @resource = build(:multi_email_user)
        refute @resource.as_json.key?('tokens'),
               'tokens should be excluded from as_json output'
      end

      test 'email is included in as_json via :methods delegation' do
        # MultiEmailUser overrides as_json to include :email as a method so
        # the delegated primary email appears in API responses.
        @resource = build(:multi_email_user)
        json_keys = @resource.as_json.keys
        assert json_keys.include?('email'),
               "Expected 'email' in as_json output, got: #{json_keys.inspect}"
      end
    end

    # -------------------------------------------------------------------------
    # Creation — uid is required for non-email (OAuth) providers
    # -------------------------------------------------------------------------
    describe 'creation' do
      test 'save fails when uid is missing for OAuth provider' do
        # For email providers, uid is auto-synced from the primary email via the
        # sync_uid before_save callback.  The explicit presence validation on uid
        # only applies to non-email (OAuth) providers.
        @resource = MultiEmailUser.new(provider: 'facebook')
        @resource.uid = nil
        @resource.save

        assert @resource.errors[:uid].present?,
               'Expected a validation error on :uid when provider is non-email and uid is nil'
      end
    end

    # -------------------------------------------------------------------------
    # Email association and delegation
    # -------------------------------------------------------------------------
    describe 'email association' do
      test 'email record is created when user is registered via the gem' do
        # Simulate what the gem does: build a user and add an email record via
        # the association directly (mirrors what :multi_email_authenticatable
        # does internally on registration).
        @resource = MultiEmailUser.new(provider: 'email', uid: '')
        @resource.emails.build(email: Faker::Internet.unique.email, primary: true)
        @resource.password = @resource.password_confirmation = 'password123'
        @resource.save(validate: false) # bypass confirmable for unit test

        assert_equal 1, @resource.emails.count
      end

      test 'primary email record is flagged as primary' do
        @resource = MultiEmailUser.new(provider: 'email', uid: '')
        email_addr = Faker::Internet.unique.email
        @resource.emails.build(email: email_addr, primary: true)
        @resource.password = @resource.password_confirmation = 'password123'
        @resource.save(validate: false)

        assert @resource.emails.first.primary?,
               'Expected the first email record to be marked primary'
      end

      test 'email delegation returns the primary email address' do
        @resource = MultiEmailUser.new(provider: 'email', uid: '')
        email_addr = Faker::Internet.unique.email
        @resource.emails.build(email: email_addr, primary: true)
        @resource.password = @resource.password_confirmation = 'password123'
        @resource.save(validate: false)

        assert_equal email_addr, @resource.email
      end
    end

    # -------------------------------------------------------------------------
    # Token management — mirrors user_test.rb but for MultiEmailUser
    # -------------------------------------------------------------------------
    describe 'token expiry' do
      before do
        @resource = MultiEmailUser.new(provider: 'email', uid: '')
        email_addr = Faker::Internet.unique.email
        @resource.emails.build(email: email_addr, primary: true)
        @resource.password = @resource.password_confirmation = 'password123'
        @resource.save(validate: false)

        @auth_headers = @resource.create_new_auth_token
        @token        = @auth_headers['access-token']
        @client_id    = @auth_headers['client']
      end

      test 'token_is_current? returns true for a fresh token' do
        assert @resource.token_is_current?(@token, @client_id)
      end

      test 'token_is_current? returns false for an expired token' do
        @resource.tokens[@client_id]['expiry'] = Time.zone.now.to_i - 10.seconds
        refute @resource.token_is_current?(@token, @client_id)
      end
    end

    describe 'valid_token?' do
      before do
        @resource = MultiEmailUser.new(provider: 'email', uid: '')
        @resource.emails.build(email: Faker::Internet.unique.email, primary: true)
        @resource.password = @resource.password_confirmation = 'password123'
        @resource.save(validate: false)

        @auth_headers = @resource.create_new_auth_token
        @token        = @auth_headers['access-token']
        @client_id    = @auth_headers['client']
      end

      test 'returns true for a valid token/client pair' do
        assert @resource.valid_token?(@token, @client_id)
      end

      test 'returns false when client does not exist' do
        refute @resource.valid_token?(@token, 'nonexistent_client')
      end

      test 'returns false when token is wrong' do
        refute @resource.valid_token?('wrong_token', @client_id)
      end
    end

    describe 'expired tokens are destroyed on save' do
      before do
        @resource = MultiEmailUser.new(provider: 'email', uid: '')
        @resource.emails.build(email: Faker::Internet.unique.email, primary: true)
        @resource.password = @resource.password_confirmation = 'password123'
        @resource.save(validate: false)

        @old_auth_headers = @resource.create_new_auth_token
        @new_auth_headers = @resource.create_new_auth_token
        expire_token(@resource, @old_auth_headers['client'])
      end

      test 'expired token is removed from tokens' do
        refute @resource.tokens[@old_auth_headers['client']],
               'Expired token should have been removed'
      end

      test 'current token is not removed' do
        assert @resource.tokens[@new_auth_headers['client']],
               'Current token should still be present'
      end
    end

    describe 'nil tokens are handled properly' do
      before do
        @resource = MultiEmailUser.new(provider: 'email', uid: '')
        @resource.emails.build(email: Faker::Internet.unique.email, primary: true)
        @resource.password = @resource.password_confirmation = 'password123'
        @resource.save(validate: false)
      end

      test 'tokens can be set to nil and record still saves' do
        @resource.tokens = nil
        assert @resource.save
      end
    end

    # -------------------------------------------------------------------------
    # Password requirements
    # -------------------------------------------------------------------------
    describe 'password_required?' do
      test 'password is not required for OAuth (non-email) provider' do
        @resource = MultiEmailUser.new(provider: 'facebook', uid: '12345')
        refute @resource.password_required?
      end

      test 'password is required for email provider' do
        @resource = MultiEmailUser.new(provider: 'email', uid: 'test@example.com')
        assert @resource.password_required?
      end
    end
  end
end
