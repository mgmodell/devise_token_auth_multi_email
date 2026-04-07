# frozen_string_literal: true

# MultiEmailUser demonstrates a model that uses devise-multi_email alongside
# DeviseTokenAuth.  Email uniqueness is enforced via the emails association/table
# (managed by Devise::MultiEmail::ParentModelExtensions) rather than by the
# column-level uniqueness validation that standard models carry.
#
# IMPORTANT ordering rules:
#   1. has_many :emails must be declared BEFORE the multi_email devise modules so
#      Devise::MultiEmail::ParentModelExtensions can reflect on the association.
#   2. The multi_email devise modules must be called BEFORE including
#      DeviseTokenAuth::Concerns::User so the concern skips its own devise call
#      (it checks method_defined?(:devise_modules) to decide whether to call devise).
class MultiEmailUser < ActiveRecord::Base
  # 1. Association first — ParentModelExtensions reflects on it at include time.
  #    Rails infers the FK as `multi_email_user_id` from the parent class name.
  has_many :emails,
           class_name: 'MultiEmailUserEmail',
           dependent:  :destroy

  # 2. multi_email devise modules — these include Devise::MultiEmail::ParentModelExtensions
  #    which adds multi_email_association, find_by_email, and related helpers.
  devise :multi_email_authenticatable, :registerable,
         :recoverable, :multi_email_validatable, :multi_email_confirmable

  # 3. DeviseTokenAuth concern — sees devise_modules already defined, skips its
  #    own devise call, and adds token management, OmniAuth callbacks, etc.
  include DeviseTokenAuth::Concerns::User
end
