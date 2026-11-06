# frozen_string_literal: true

# Someone a community's moderators have stopped from posting there.
#
# Scoped to the community, not the site: `ModerationReport` resolving against
# the global `TrustScore` is a different lever, held by a different person, and
# a city forum where one community's moderator can silence someone everywhere is
# not a thing anyone should build.
class CommunityBan < ApplicationRecord
  include Shared::Notifiable

  belongs_to :community
  belongs_to :user
  belongs_to :banned_by, class_name: "User"

  validates :user_id, uniqueness: { scope: :community_id }
  validates :reason, length: { maximum: 280 }
  validate :not_a_moderator

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  after_create_commit :tell_them

  def permanent? = expires_at.nil?
  def expired? = expires_at.present? && expires_at <= Time.current

  private

  # A moderator banning another moderator is a fight the app should not settle.
  # Demote first, which is an owner-only action, and the ban becomes possible.
  def not_a_moderator
    return if community.blank? || user.blank?
    return unless community.moderator?(user) || community.owner?(user)

    errors.add(:user, :is_a_moderator)
  end

  # Told, with the reason and whether it ends. A ban nobody is informed of reads
  # as the site being broken — the person keeps writing posts that vanish.
  def tell_them
    deliver_notification(
      user,
      title: I18n.t("community.banned_notification", community: strict_safe(:community)&.name),
      body: [ reason.presence, expiry_line ].compact.join(" — "),
      source: strict_safe(:community),
      kind: "alert"
    )
  end

  def expiry_line
    permanent? ? I18n.t("community.ban_permanent") : I18n.t("community.ban_until", time: I18n.l(expires_at, format: :event))
  end
end
