# frozen_string_literal: true

# Email record for MultiEmailUser.  Each row represents one email address
# that belongs to a MultiEmailUser; the primary_email_record column marks the
# address currently used for authentication.
#
# Devise::MultiEmail::EmailModelExtensions (and EmailValidatable) are included
# automatically into this class by MultiEmailUser's ParentModelExtensions when
# that model is first loaded — no explicit include is needed here.
#
# The association name (:user) must match Devise::MultiEmail.parent_association_name
# (which defaults to :user).  We specify the class and FK explicitly since our
# parent model is MultiEmailUser (not User) and the FK column is multi_email_user_id.
class MultiEmailUserEmail < ActiveRecord::Base
  belongs_to :user,
             class_name:  'MultiEmailUser',
             foreign_key: :multi_email_user_id
end
