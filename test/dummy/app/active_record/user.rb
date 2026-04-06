# frozen_string_literal: true

class User < ActiveRecord::Base
  include DeviseTokenAuth::Concerns::User
  include FavoriteColor

  # When devise-multi_email is loaded the concern skips the email uniqueness
  # validation, expecting the gem to manage it via a separate emails table.
  # Since this dummy app does not set up that table, we add the validation here
  # so that duplicate registrations are rejected at the model level (preventing
  # DB-level UniqueViolation errors that abort the PostgreSQL test transaction).
  validates :email, uniqueness: { scope: :provider, case_sensitive: false },
                    on: :create, allow_blank: true
end
