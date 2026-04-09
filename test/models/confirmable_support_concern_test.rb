# frozen_string_literal: true

require 'test_helper'

# Unit tests for DeviseTokenAuth::Concerns::ConfirmableSupport.
#
# This concern is included into models that have DeviseTokenAuth's
# send_confirmation_email setting enabled along with Devise's :confirmable
# module.  It overrides postpone_email_change? to avoid relying on
# devise_will_save_change_to_email?, and exposes email_value_in_database
# as a Rails-version-safe helper.
#
# These tests use ConfirmableUser, which is the only model in the test app
# that has :confirmable and triggers ConfirmableSupport inclusion.
return unless DEVISE_TOKEN_AUTH_ORM == :active_record

class ConfirmableSupportConcernTest < ActiveSupport::TestCase
  describe DeviseTokenAuth::Concerns::ConfirmableSupport do
    # ConfirmableUser includes ConfirmableSupport via the
    # DeviseTokenAuth.send_confirmation_email + :confirmable check in user.rb.
    test 'ConfirmableUser includes ConfirmableSupport' do
      assert ConfirmableUser.ancestors.include?(DeviseTokenAuth::Concerns::ConfirmableSupport),
             'Expected ConfirmableUser to include ConfirmableSupport'
    end

    # -------------------------------------------------------------------------
    # email_value_in_database (protected)
    # -------------------------------------------------------------------------
    describe '#email_value_in_database' do
      test 'returns the persisted email (not an in-memory change)' do
        original_email = 'original@example.com'
        resource = create(:confirmable_user, email: original_email)

        # Change email in memory only — do not save
        resource.email = 'inmemory@example.com'

        persisted = resource.send(:email_value_in_database)
        assert_equal original_email, persisted,
                     'email_value_in_database should return the DB value, not the in-memory change'
      end

      test 'returns nil for a brand-new (unsaved) record' do
        resource = ConfirmableUser.new(email: 'new@example.com')
        result = resource.send(:email_value_in_database)
        # A new record has no persisted value — expect nil or blank string
        assert result.nil? || result == '',
               "Expected nil or '' for unsaved record, got: #{result.inspect}"
      end
    end

    # -------------------------------------------------------------------------
    # postpone_email_change? (public via override)
    # -------------------------------------------------------------------------
    describe '#postpone_email_change?' do
      test 'returns true when reconfirmable is enabled and email has changed' do
        resource = create(:confirmable_user, email: 'before@example.com')

        # Change email but do not save — postpone_email_change? inspects pending
        # changes before the save happens.
        resource.email = 'after@example.com'

        assert resource.postpone_email_change?,
               'Expected postpone_email_change? to return true when email changed and reconfirmable is on'
      end

      test 'returns false when reconfirmable is disabled' do
        swap ConfirmableUser, reconfirmable: false do
          resource = create(:confirmable_user, email: 'reconf@example.com')
          resource.email = 'reconf_new@example.com'
          refute resource.postpone_email_change?,
                 'Expected postpone_email_change? to return false when reconfirmable is off'
        end
      end

      test 'returns false when email has not changed' do
        resource = create(:confirmable_user, email: 'same@example.com')
        # No change to email
        refute resource.postpone_email_change?,
               'Expected postpone_email_change? to return false when email is unchanged'
      end

      test 'resets @bypass_confirmation_postpone after the check' do
        resource = create(:confirmable_user, email: 'reset_test@example.com')
        resource.instance_variable_set(:@bypass_confirmation_postpone, true)
        resource.email = 'reset_new@example.com'

        # The flag bypasses the postpone on the first call
        refute resource.postpone_email_change?,
               'Expected postpone_email_change? to return false when bypass flag is set'

        # After the first call the flag should be cleared
        refute resource.instance_variable_get(:@bypass_confirmation_postpone),
               '@bypass_confirmation_postpone should be reset to false after the call'
      end
    end
  end
end
