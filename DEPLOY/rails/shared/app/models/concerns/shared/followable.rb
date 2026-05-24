# frozen_string_literal: true

module Shared
  module Followable
    extend ActiveSupport::Concern

    included do
      has_many :follows_received, as: :followable, class_name: "Follow", dependent: :destroy
    end

    def followed_by?(user)
      return false unless user

      follows_received.exists?(follower: user)
    end

    def followers_count
      follows_received.count
    end
  end
end
