# frozen_string_literal: true

# MultiEmailUser demonstrates a model that uses devise-multi_email alongside
# DeviseTokenAuth.  Email uniqueness is enforced via the emails association
# (managed by Devise::MultiEmail::ParentModelConcern) rather than by the
# column-level uniqueness validation that standard models carry.
class MultiEmailUser < ActiveRecord::Base
  include DeviseTokenAuth::Concerns::User
  include Devise::MultiEmail::ParentModelConcern

  # The association name must match Devise::MultiEmail.emails_association_name
  # (default: :emails).  We point it at our concrete email class and FK.
  has_many :emails,
           class_name:  'MultiEmailUserEmail',
           foreign_key: :multi_email_user_id,
           dependent:   :destroy
end
