# frozen_string_literal: true

module DeviseTokenAuth::Concerns::UserOmniauthCallbacks
  extend ActiveSupport::Concern

  included do
    validates :email, presence: true, if: lambda { uid_and_provider_defined? && email_provider? }
    validates :email, :devise_token_auth_email => true, allow_nil: true, allow_blank: true, if: lambda { uid_and_provider_defined? && email_provider? }
    validates_presence_of :uid, if: lambda { uid_and_provider_defined? && !email_provider? }

    # Only validate email uniqueness for models that do NOT use devise-multi_email.
    # Multi-email models manage uniqueness via the emails association table instead.
    #
    # The check is done at runtime (inside the lambda) rather than at class-load
    # time, so that it works correctly regardless of the order in which modules are
    # included.  If the class responds to :multi_email_association at the point the
    # validation is about to run, we know this is a multi-email model and skip the
    # check.  This also avoids calling column_for_attribute(:email) on a model that
    # has no email column, which would otherwise cause MySQL to call
    # nil.case_sensitive? and raise a NoMethodError.
    validates :email, uniqueness: { case_sensitive: false, scope: :provider }, on: :create,
              if: lambda { uid_and_provider_defined? && email_provider? && !self.class.respond_to?(:multi_email_association) }

    # keep uid in sync with email
    before_save :sync_uid
    before_create :sync_uid
  end

  protected

  def uid_and_provider_defined?
    defined?(provider) && defined?(uid)
  end

  def email_provider?
    provider == 'email'
  end

  def sync_uid
    unless self.new_record?
      return if devise_modules.include?(:confirmable) && !@bypass_confirmation_postpone && postpone_email_change?
    end
    self.uid = email if uid_and_provider_defined? && email_provider?
  end
end
