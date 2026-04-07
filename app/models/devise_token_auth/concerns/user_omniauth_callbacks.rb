# frozen_string_literal: true

module DeviseTokenAuth::Concerns::UserOmniauthCallbacks
  extend ActiveSupport::Concern

  included do
    validates :email, presence: true, if: lambda { uid_and_provider_defined? && email_provider? }
    validates :email, :devise_token_auth_email => true, allow_nil: true, allow_blank: true, if: lambda { uid_and_provider_defined? && email_provider? }
    validates_presence_of :uid, if: lambda { uid_and_provider_defined? && !email_provider? }

    # Only skip the uniqueness validation for models that use devise-multi_email
    # (detected by the presence of the multi_email_association class method, which
    # Devise::MultiEmail::ParentModelExtensions adds via :multi_email_authenticatable).
    # Standard models always validate; multi_email models manage uniqueness via the
    # emails association table instead.
    unless Gem.loaded_specs['devise-multi_email'] && respond_to?(:multi_email_association)
      # only validate unique emails among email registration users
      validates :email, uniqueness: { case_sensitive: false, scope: :provider }, on: :create, if: lambda { uid_and_provider_defined? && email_provider? }
    end

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
