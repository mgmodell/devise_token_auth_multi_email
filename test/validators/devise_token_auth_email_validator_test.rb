# frozen_string_literal: true

require 'test_helper'

class DeviseTokenAuthEmailValidatorTest < ActiveSupport::TestCase
  # A minimal ActiveModel object so we can test validate_each without a DB.
  class EmailHolder
    include ActiveModel::Validations

    attr_accessor :email

    validates :email, devise_token_auth_email: true

    def initialize(email)
      @email = email
    end
  end

  class EmailHolderWithCustomMessage
    include ActiveModel::Validations

    attr_accessor :email

    validates :email, devise_token_auth_email: { message: 'is not a real email' }

    def initialize(email)
      @email = email
    end
  end

  # ---------------------------------------------------------------------------
  # .validate? (class method)
  # ---------------------------------------------------------------------------
  describe '.validate?' do
    describe 'valid email addresses' do
      [
        'user@example.com',
        'User@Example.COM',
        'user+tag@sub.example.org',
        'u@x.io',
        'first.last@domain.co.uk',
        'user-name@my-domain.travel'
      ].each do |email|
        test "accepts #{email}" do
          assert DeviseTokenAuthEmailValidator.validate?(email),
                 "Expected '#{email}' to be valid"
        end
      end
    end

    describe 'invalid email addresses' do
      [
        nil,
        '',
        'plainaddress',
        '@missing-local.org',
        'user@',
        'user@.com',
        'user space@example.com',
        'user@exam_ple.com'
      ].each do |email|
        test "rejects #{email.inspect}" do
          refute DeviseTokenAuthEmailValidator.validate?(email),
                 "Expected #{email.inspect} to be invalid"
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # validate_each (instance behaviour via ActiveModel::Validations)
  # ---------------------------------------------------------------------------
  describe 'validate_each' do
    describe 'with a valid email' do
      test 'does not add an error' do
        holder = EmailHolder.new('user@example.com')
        assert holder.valid?, "Expected holder to be valid but got: #{holder.errors.full_messages}"
        assert_empty holder.errors[:email]
      end
    end

    describe 'with an invalid email' do
      test 'adds an error to the attribute' do
        holder = EmailHolder.new('not-an-email')
        refute holder.valid?
        assert_not_empty holder.errors[:email]
      end

      test 'error message uses I18n not_email key with invalid fallback' do
        holder = EmailHolder.new('bad')
        holder.valid?
        expected = I18n.t(:'errors.messages.not_email', default: :'errors.messages.invalid')
        assert_includes holder.errors[:email], expected
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Custom :message option
  # ---------------------------------------------------------------------------
  describe 'custom message option' do
    test 'uses the supplied message instead of the I18n default' do
      holder = EmailHolderWithCustomMessage.new('not-an-email')
      refute holder.valid?
      assert_includes holder.errors[:email], 'is not a real email'
    end

    test 'does not add any error when the email is valid' do
      holder = EmailHolderWithCustomMessage.new('user@example.com')
      assert holder.valid?
      assert_empty holder.errors[:email]
    end
  end
end
