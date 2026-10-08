# frozen_string_literal: true

class CommunityMembership < ApplicationRecord
  include Shared::Notifiable

  ROLES = %w[member moderator owner].freeze

  belongs_to :user
  belongs_to :community, counter_cache: :members_count

  validates :user_id, uniqueness: { scope: :community_id }
  validates :role, inclusion: { in: ROLES }
  validate :owner_cannot_be_demoted_to_nothing, on: :update

  scope :moderating, -> { where(role: %w[moderator owner]) }

  def moderator? = role.in?(%w[moderator owner])
  def owner? = role == "owner"

  private

  # A community with no owner has nobody who can appoint a moderator, and
  # nothing else in the app can create one. Losing the last owner is therefore
  # not a state to recover from later — it is one to refuse now.
  def owner_cannot_be_demoted_to_nothing
    return unless role_changed? && role_was == "owner"
    return if community.community_memberships.where(role: "owner").where.not(id: id).exists?

    errors.add(:role, :last_owner)
  end
end
