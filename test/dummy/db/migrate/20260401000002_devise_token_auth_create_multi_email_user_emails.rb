# frozen_string_literal: true

class DeviseTokenAuthCreateMultiEmailUserEmails < ActiveRecord::Migration[7.0]
  def change
    create_table(:multi_email_user_emails) do |t|
      t.references :multi_email_user, null: false, foreign_key: true
      t.string  :email,                null: false
      t.boolean :primary_email_record, null: false, default: false

      t.timestamps
    end

    add_index :multi_email_user_emails, :email,                                   unique: true
    add_index :multi_email_user_emails, [:multi_email_user_id, :primary_email_record],
              name: 'index_multi_email_user_emails_on_user_and_primary'
  end
end
