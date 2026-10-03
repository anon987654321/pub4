# frozen_string_literal: true

class User
  module TvAssociations
    extend ActiveSupport::Concern

    included do
      has_many :tv_channels, class_name: "Tv::Channel", dependent: :destroy
      has_many :tv_subscriptions, class_name: "Tv::Subscription", dependent: :destroy
      has_many :subscribed_channels, through: :tv_subscriptions, source: :tv_channel
      # Watch history. The rows were already being written by videos#show with
      # no association on this side, so tv_view_events.user_id (NOT NULL) had
      # nothing cascading it on account deletion either.
      has_many :tv_view_events, class_name: "Tv::ViewEvent", dependent: :destroy
    end
  end
end
