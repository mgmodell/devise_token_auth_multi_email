# frozen_string_literal: true

require 'test_helper'

# Unit tests for methods defined in DeviseTokenAuth::Concerns::User that are
# not already exercised by user_test.rb or the controller-level tests.
#
# Covered here:
#   - build_auth_headers / build_bearer_token
#   - confirmed?
#   - token_validation_response
#   - extend_batch_buffer
#   - remove_tokens_after_password_reset / should_remove_tokens_after_password_reset?
#   - does_token_match?
#   - tokens_match? (class-level cache)
class UserConcernMethodsTest < ActiveSupport::TestCase
  describe DeviseTokenAuth::Concerns::User do
    # -------------------------------------------------------------------------
    # Setup helpers
    # -------------------------------------------------------------------------
    def build_confirmed_user
      create(:user, :confirmed)
    end

    # -------------------------------------------------------------------------
    # build_auth_headers / build_bearer_token
    # -------------------------------------------------------------------------
    describe '#build_auth_headers' do
      before do
        @resource    = build_confirmed_user
        @auth        = @resource.create_new_auth_token
        @client_id   = @auth['client']
        @token       = @auth['access-token']
        @headers     = @resource.build_auth_headers(@token, @client_id)
      end

      test 'includes access-token key' do
        assert @headers.key?(DeviseTokenAuth.headers_names[:'access-token'])
      end

      test 'includes token-type key' do
        assert @headers.key?(DeviseTokenAuth.headers_names[:'token-type'])
      end

      test 'includes client key' do
        assert @headers.key?(DeviseTokenAuth.headers_names[:'client'])
      end

      test 'includes expiry key' do
        assert @headers.key?(DeviseTokenAuth.headers_names[:'expiry'])
      end

      test 'includes uid key' do
        assert @headers.key?(DeviseTokenAuth.headers_names[:'uid'])
      end

      test 'uid value matches resource uid' do
        assert_equal @resource.uid, @headers[DeviseTokenAuth.headers_names[:'uid']]
      end

      test 'access-token value matches token' do
        assert_equal @token, @headers[DeviseTokenAuth.headers_names[:'access-token']]
      end

      test 'token-type is Bearer' do
        assert_equal 'Bearer', @headers[DeviseTokenAuth.headers_names[:'token-type']]
      end
    end

    describe '#build_bearer_token' do
      before do
        @resource  = build_confirmed_user
        @auth      = @resource.create_new_auth_token
        @client_id = @auth['client']
        @token     = @auth['access-token']
      end

      test 'returns a hash with an Authorization key when cookies are disabled' do
        DeviseTokenAuth.cookie_enabled = false
        auth_payload = { 'uid' => @resource.uid }
        result = @resource.build_bearer_token(auth_payload)
        assert result.key?(DeviseTokenAuth.headers_names[:'authorization'])
      end

      test 'Authorization value starts with "Bearer "' do
        DeviseTokenAuth.cookie_enabled = false
        auth_payload = { 'uid' => @resource.uid }
        result = @resource.build_bearer_token(auth_payload)
        assert result[DeviseTokenAuth.headers_names[:'authorization']].start_with?('Bearer ')
      end

      test 'returns an empty hash when cookie_enabled is true' do
        DeviseTokenAuth.cookie_enabled = true
        auth_payload = { 'uid' => @resource.uid }
        result = @resource.build_bearer_token(auth_payload)
        assert_empty result
      ensure
        DeviseTokenAuth.cookie_enabled = false
      end
    end

    # -------------------------------------------------------------------------
    # confirmed?
    # -------------------------------------------------------------------------
    describe '#confirmed?' do
      test 'returns true for a user without :confirmable devise module' do
        # User does not include :confirmable, so confirmed? must return true.
        resource = build_confirmed_user
        refute resource.devise_modules.include?(:confirmable)
        assert resource.confirmed?
      end

      if DEVISE_TOKEN_AUTH_ORM == :active_record
        test 'returns true for a ConfirmableUser that has been confirmed' do
          resource = create(:confirmable_user)
          resource.confirm
          assert resource.confirmed?
        end

        test 'returns false for a ConfirmableUser that has not been confirmed' do
          resource = create(:confirmable_user)
          # Reload to drop any in-memory state set during creation
          resource.reload
          refute resource.confirmed?
        end
      end
    end

    # -------------------------------------------------------------------------
    # token_validation_response
    # -------------------------------------------------------------------------
    describe '#token_validation_response' do
      before do
        @resource = build_confirmed_user
        @response = @resource.token_validation_response
      end

      test 'returns a hash' do
        assert_kind_of Hash, @response
      end

      test 'does not include :tokens key' do
        refute @response.key?('tokens'), 'tokens should be excluded from token_validation_response'
      end

      test 'does not include :created_at key' do
        refute @response.key?('created_at'), 'created_at should be excluded'
      end

      test 'does not include :updated_at key' do
        refute @response.key?('updated_at'), 'updated_at should be excluded'
      end

      test 'includes the email key' do
        assert @response.key?('email')
      end

      test 'includes the uid key' do
        assert @response.key?('uid')
      end
    end

    # -------------------------------------------------------------------------
    # extend_batch_buffer
    # -------------------------------------------------------------------------
    describe '#extend_batch_buffer' do
      before do
        @resource  = build_confirmed_user
        @auth      = @resource.create_new_auth_token
        @client_id = @auth['client']
        @token     = @auth['access-token']
        age_token(@resource, @client_id)
      end

      test 'returns a hash with auth header keys' do
        result = @resource.extend_batch_buffer(@token, @client_id)
        assert result.key?(DeviseTokenAuth.headers_names[:'access-token'])
      end

      test 'updates the updated_at timestamp for the client token' do
        # age_token set updated_at to the past; extend_batch_buffer should
        # refresh it to approximately now.
        @resource.extend_batch_buffer(@token, @client_id)
        updated_at = @resource.tokens[@client_id]['updated_at']
        # updated_at should now be within the last 5 seconds
        assert updated_at.to_time >= Time.zone.now - 5.seconds,
               'updated_at should be refreshed to approximately now by extend_batch_buffer'
      end

      test 'persists the token record to the database' do
        @resource.extend_batch_buffer(@token, @client_id)
        reloaded = @resource.class.find(@resource.id)
        assert reloaded.tokens[@client_id]
      end
    end

    # -------------------------------------------------------------------------
    # does_token_match?
    # -------------------------------------------------------------------------
    describe '#does_token_match?' do
      before do
        @resource  = build_confirmed_user
        @auth      = @resource.create_new_auth_token
        @client_id = @auth['client']
        @token     = @auth['access-token']
      end

      test 'returns false when token_hash is nil' do
        refute @resource.does_token_match?(nil, @token)
      end

      test 'returns false when token does not match' do
        token_hash = @resource.tokens[@client_id]['token']
        refute @resource.does_token_match?(token_hash, 'wrong_token')
      end

      test 'returns true when token matches its hash' do
        # Obtain the raw token before it gets rotated; use the original
        # auth headers directly since create_new_auth_token returns the
        # plaintext token in the headers hash.
        token_hash = @resource.tokens[@client_id]['token']
        assert @resource.does_token_match?(token_hash, @token)
      end
    end

    # -------------------------------------------------------------------------
    # DeviseTokenAuth::Concerns::User.tokens_match? (class-level)
    # -------------------------------------------------------------------------
    describe '.tokens_match?' do
      test 'returns truthy when hash matches token' do
        raw = DeviseTokenAuth::TokenFactory.create
        assert DeviseTokenAuth::Concerns::User.tokens_match?(raw.token_hash, raw.token)
      end

      test 'returns falsy when hash does not match token' do
        raw = DeviseTokenAuth::TokenFactory.create
        refute DeviseTokenAuth::Concerns::User.tokens_match?(raw.token_hash, 'wrong')
      end

      test 'populates and reuses the equality cache' do
        raw = DeviseTokenAuth::TokenFactory.create
        # Reset the cache to isolate this test
        DeviseTokenAuth::Concerns::User.instance_variable_set(:@token_equality_cache, nil)

        # First call — cache is empty, result computed from BCrypt
        first = DeviseTokenAuth::Concerns::User.tokens_match?(raw.token_hash, raw.token)
        cache_after_first = DeviseTokenAuth::Concerns::User.instance_variable_get(:@token_equality_cache)

        assert first, 'Expected tokens_match? to return truthy for a matching pair'
        assert_equal 1, cache_after_first.size, 'Cache should contain one entry after first call'

        # Second call — same inputs, result served from cache (no BCrypt re-computation)
        second = DeviseTokenAuth::Concerns::User.tokens_match?(raw.token_hash, raw.token)
        cache_after_second = DeviseTokenAuth::Concerns::User.instance_variable_get(:@token_equality_cache)

        assert second, 'Cached result should also be truthy'
        assert_equal 1, cache_after_second.size, 'Cache size should remain 1 (no duplicate entry)'
      end
    end

    # -------------------------------------------------------------------------
    # should_remove_tokens_after_password_reset? / remove_tokens_after_password_reset
    # -------------------------------------------------------------------------
    if DEVISE_TOKEN_AUTH_ORM == :active_record
      describe '#should_remove_tokens_after_password_reset?' do
        before do
          @resource = build_confirmed_user
        end

        test 'returns false when remove_tokens_after_password_reset is false' do
          DeviseTokenAuth.remove_tokens_after_password_reset = false
          refute @resource.send(:should_remove_tokens_after_password_reset?)
        end

        test 'returns false when remove_tokens_after_password_reset is true but password has not changed' do
          DeviseTokenAuth.remove_tokens_after_password_reset = true
          # Reload so there is no pending change
          @resource.reload
          refute @resource.send(:should_remove_tokens_after_password_reset?)
        ensure
          DeviseTokenAuth.remove_tokens_after_password_reset = false
        end

        test 'returns true when remove_tokens_after_password_reset is true and password changed' do
          DeviseTokenAuth.remove_tokens_after_password_reset = true
          @resource.password = @resource.password_confirmation = 'NewSecret999!'
          assert @resource.send(:should_remove_tokens_after_password_reset?)
        ensure
          DeviseTokenAuth.remove_tokens_after_password_reset = false
        end
      end

      describe '#remove_tokens_after_password_reset' do
        before do
          @resource = build_confirmed_user
          # Create multiple tokens on multiple clients
          3.times { @resource.create_new_auth_token }
          @resource.save!
        end

        test 'keeps only the most recent token when password changes and setting is enabled' do
          DeviseTokenAuth.remove_tokens_after_password_reset = true

          # Simulate a password change
          @resource.password = @resource.password_confirmation = 'NewSecret999!'
          @resource.save!

          assert_equal 1, @resource.tokens.count,
                       'All but the most-recent token should be removed after password reset'
        ensure
          DeviseTokenAuth.remove_tokens_after_password_reset = false
        end

        test 'does not alter tokens when setting is disabled' do
          DeviseTokenAuth.remove_tokens_after_password_reset = false
          count_before = @resource.tokens.count

          @resource.password = @resource.password_confirmation = 'NewSecret999!'
          @resource.save!

          assert_equal count_before, @resource.tokens.count
        end
      end
    end
  end
end
