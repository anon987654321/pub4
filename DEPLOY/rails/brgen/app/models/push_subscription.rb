# frozen_string_literal: true

class PushSubscription < ApplicationRecord
  belongs_to :user
  validates :endpoint, presence: true, uniqueness: { scope: :user_id }
  validates :p256dh, :auth, presence: true
end
