# frozen_string_literal: true

class CommunityMembership < ApplicationRecord
  belongs_to :user
  belongs_to :community

  validates :user_id, uniqueness: { scope: :community_id }
end
