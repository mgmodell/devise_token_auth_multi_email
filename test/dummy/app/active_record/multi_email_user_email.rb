# frozen_string_literal: true

# Email record for MultiEmailUser.  Each row represents one email address
# that belongs to a MultiEmailUser; the primary_email_record flag marks the
# address currently used for authentication.
class MultiEmailUserEmail < ActiveRecord::Base
  include Devise::MultiEmail::EmailModelConcern

  belongs_to :multi_email_user
end
