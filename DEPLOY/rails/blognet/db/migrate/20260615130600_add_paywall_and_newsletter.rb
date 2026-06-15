# frozen_string_literal: true

class AddPaywallAndNewsletter < ActiveRecord::Migration[8.1]
  def change
    add_column :blogs, :paywall_enabled, :boolean, default: false, null: false
    add_column :blogs, :free_article_limit, :integer, default: 3
    add_column :posts, :paywalled, :boolean, default: false, null: false

    create_table :article_views do |t|
      t.references :post, null: false, foreign_key: true
      t.string :viewer_token, null: false
      t.timestamps
    end
    add_index :article_views, %i[post_id viewer_token], unique: true

    create_table :newsletter_subscriptions do |t|
      t.references :blog, null: false, foreign_key: true
      t.string :email, null: false
      t.string :token, null: false
      t.boolean :active, default: true, null: false
      t.datetime :confirmed_at
      t.timestamps
    end
    add_index :newsletter_subscriptions, %i[blog_id email], unique: true
    add_index :newsletter_subscriptions, :token, unique: true

    create_table :subscriptions do |t|
      t.references :user, foreign_key: true
      t.references :blog, null: false, foreign_key: true
      t.string :stripe_checkout_session_id
      t.string :status, default: "inactive"
      t.datetime :expires_at
      t.timestamps
    end
  end
end