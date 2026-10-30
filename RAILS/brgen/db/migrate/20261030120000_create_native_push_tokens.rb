# frozen_string_literal: true

# The iOS shell is a WKWebView, which has no Push API, so its readers reach a
# lock screen only through APNs and a device token. A table of its own rather
# than nullable web-push columns: an APNs token has no endpoint and no keys.
class CreateNativePushTokens < ActiveRecord::Migration[8.2]
  def change
    create_table :native_push_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false
      t.string :environment, null: false, default: "production"
      t.timestamps
    end
    add_index :native_push_tokens, :token, unique: true
  end
end
