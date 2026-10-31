# frozen_string_literal: true

# Shared::BillingSubscription: one row per Stripe subscription, kept in step by
# the webhook (Shared::StripeBilling). Plans are data in __shared/config/plans.yml.
class CreateBillingSubscriptions < ActiveRecord::Migration[8.2]
  def change
    create_table :billing_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :plan_key, null: false
      t.string :status, null: false
      t.string :stripe_subscription_id, null: false
      t.string :stripe_customer_id
      t.datetime :current_period_end
      t.boolean :cancel_at_period_end, null: false, default: false
      t.timestamps
    end

    add_index :billing_subscriptions, :stripe_subscription_id, unique: true
    add_index :billing_subscriptions, %i[user_id status]
  end
end
