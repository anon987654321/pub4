# frozen_string_literal: true

class Tv::Subscription < ApplicationRecord
  belongs_to :user
  belongs_to :channel, class_name: "Tv::Channel", foreign_key: :tv_channel_id
  validates :user_id, uniqueness: { scope: :tv_channel_id }
end
