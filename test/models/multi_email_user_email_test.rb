# frozen_string_literal: true

require 'test_helper'

# Tests for the MultiEmailUserEmail model — the email-record side of the
# MultiEmailUser multi-email relationship.  These tests are ActiveRecord-only
# because the model and its table only exist in AR runs.
return unless DEVISE_TOKEN_AUTH_ORM == :active_record

class MultiEmailUserEmailTest < ActiveSupport::TestCase
  describe MultiEmailUserEmail do
    # -------------------------------------------------------------------------
    # Association
    # -------------------------------------------------------------------------
    describe 'association' do
      test 'belongs_to user association points to MultiEmailUser' do
        reflection = MultiEmailUserEmail.reflect_on_association(:user)
        assert reflection, 'Expected a :user belongs_to association'
        assert_equal 'MultiEmailUser', reflection.class_name
      end

      test 'foreign key for the user association is multi_email_user_id' do
        reflection = MultiEmailUserEmail.reflect_on_association(:user)
        assert_equal 'multi_email_user_id', reflection.foreign_key.to_s
      end

      test 'email record is destroyed when parent user is destroyed' do
        user = MultiEmailUser.new(provider: 'email', uid: '')
        user.emails.build(email: Faker::Internet.unique.email, primary: true)
        user.password = user.password_confirmation = 'password123'
        user.save(validate: false)

        email_id = user.emails.first.id
        user.destroy

        refute MultiEmailUserEmail.exists?(email_id),
               'Email record should be destroyed when the parent user is destroyed'
      end
    end

    # -------------------------------------------------------------------------
    # Primary flag
    # -------------------------------------------------------------------------
    describe 'primary column' do
      test 'primary? returns true when primary is true' do
        email_record = MultiEmailUserEmail.new(primary: true)
        assert email_record.primary?
      end

      test 'primary? returns false when primary is false' do
        email_record = MultiEmailUserEmail.new(primary: false)
        refute email_record.primary?
      end

      test 'primary defaults to false' do
        email_record = MultiEmailUserEmail.new
        refute email_record.primary?,
               'primary should default to false per the migration'
      end
    end

    # -------------------------------------------------------------------------
    # Email uniqueness (added by Devise::MultiEmail::EmailValidatable)
    # -------------------------------------------------------------------------
    describe 'email uniqueness' do
      # Trigger ParentModelExtensions setup so EmailValidatable is included
      before { MultiEmailUser }

      test 'has an email UniquenessValidator (added by EmailValidatable)' do
        assert MultiEmailUserEmail.validators_on(:email).any? { |v|
          v.is_a?(ActiveRecord::Validations::UniquenessValidator)
        }, 'Expected UniquenessValidator on MultiEmailUserEmail#email from EmailValidatable'
      end

      test 'two email records with the same address are invalid' do
        shared_email = Faker::Internet.unique.email

        user1 = MultiEmailUser.new(provider: 'email', uid: '')
        user1.emails.build(email: shared_email, primary: true)
        user1.password = user1.password_confirmation = 'password123'
        user1.save(validate: false)

        user2 = MultiEmailUser.new(provider: 'email', uid: '')
        email_record = user2.emails.build(email: shared_email, primary: true)
        user2.password = user2.password_confirmation = 'password123'

        # The email record itself should fail uniqueness validation
        refute email_record.valid?,
               'Expected duplicate email record to be invalid'
        assert email_record.errors[:email].any? { |e| e.include?('taken') },
               "Expected 'taken' error on email, got: #{email_record.errors[:email].inspect}"
      end
    end
  end
end
