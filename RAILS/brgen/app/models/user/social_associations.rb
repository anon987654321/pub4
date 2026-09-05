# frozen_string_literal: true

class User
  module SocialAssociations
    extend ActiveSupport::Concern

    included do
      has_many :follows_as_followed, class_name: "Follow", foreign_key: :followed_id, dependent: :destroy,
               inverse_of: :followed
      has_many :follows_as_follower, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy,
               inverse_of: :follower
      has_many :followers, through: :follows_as_followed, source: :follower
      has_many :following, through: :follows_as_follower, source: :followed
    end
  end
end
