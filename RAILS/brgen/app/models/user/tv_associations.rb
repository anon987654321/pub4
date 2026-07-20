# frozen_string_literal: true

class User
  module TvAssociations
    extend ActiveSupport::Concern

    included do
      has_many :tv_channels, class_name: "Tv::Channel", dependent: :destroy
      has_many :tv_subscriptions, class_name: "Tv::Subscription", dependent: :destroy
      has_many :subscribed_channels, through: :tv_subscriptions, source: :tv_channel
    end
  end
end
