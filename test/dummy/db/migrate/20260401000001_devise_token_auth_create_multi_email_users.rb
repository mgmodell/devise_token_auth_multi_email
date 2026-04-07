# frozen_string_literal: true

include MigrationDatabaseHelper

class DeviseTokenAuthCreateMultiEmailUsers < ActiveRecord::Migration[7.0]
  def change
    create_table(:multi_email_users) do |t|
      ## Database authenticatable
      t.string :encrypted_password, null: false, default: ''

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at
      t.string   :reset_password_redirect_url
      t.boolean  :allow_password_change, default: false

      ## Rememberable
      t.datetime :remember_created_at

      ## Confirmable
      t.string   :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string   :unconfirmed_email

      ## User Info
      t.string :name
      t.string :nickname
      t.string :image

      ## Unique oauth id
      t.string :provider
      t.string :uid, null: false, default: ''

      ## Tokens
      if json_supported_database?
        t.json :tokens
      else
        t.text :tokens
      end

      t.timestamps
    end

    add_index :multi_email_users, [:uid, :provider],     unique: true
    add_index :multi_email_users, :reset_password_token, unique: true
    add_index :multi_email_users, :confirmation_token,   unique: true
  end
end
