# frozen_string_literal: true

class PrivacySetting < ApplicationRecord
  belongs_to :user

  # One per user, which the unique index already enforces — as a 500 rather than
  # a rejected form, since User#ensure_identity_records calls
  # create_privacy_setting! on every signup.
  validates :user_id, uniqueness: true

  enum :wardrobe_visibility, { wardrobe_private: "private", wardrobe_followers: "followers", wardrobe_public: "public" }, default: :wardrobe_private
  enum :analytics_visibility, { analytics_private: "private", analytics_aggregate: "aggregate", analytics_public: "public" }, default: :analytics_private

  def public_wardrobe? = wardrobe_public?
end
