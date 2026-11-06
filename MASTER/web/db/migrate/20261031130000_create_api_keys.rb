# frozen_string_literal: true

# ApiKey: one row per Stripe subscription to a MASTER law API plan. The key
# itself is never stored, only its SHA-256; usage counts file checks in the
# current calendar month.
class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys do |t|
      t.string :plan_key, null: false
      t.string :status, null: false
      t.string :stripe_subscription_id, null: false
      t.string :stripe_customer_id
      t.string :email
      t.string :token_digest
      t.string :token_hint
      t.datetime :current_period_end
      t.string :usage_period
      t.integer :usage_count, null: false, default: 0
      t.timestamps
    end

    add_index :api_keys, :stripe_subscription_id, unique: true
    add_index :api_keys, :token_digest, unique: true
  end
end
