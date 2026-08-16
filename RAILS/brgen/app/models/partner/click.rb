# frozen_string_literal: true

# One visit that a partner sent, and the window in which it can still earn.
#
# expires_at is stored rather than derived from the programme's attribution
# window at read time, so a merchant shortening their window does not
# retroactively void clicks that were made under the old one.
class Partner::Click < ApplicationRecord
  self.table_name = "partner_clicks"

  belongs_to :membership, class_name: "Partner::Membership"
  belongs_to :listing, class_name: "Marketplace::Listing", optional: true
  belongs_to :user, optional: true

  validates :occurred_at, :expires_at, presence: true

  scope :live, -> { where(expires_at: Time.current..) }
  scope :newest_first, -> { order(occurred_at: :desc) }

  # Record a click, unless the same visitor already has a live one for this
  # partner. A partner who gets a visitor to click the same link four times has
  # not done four times the work, and four rows would each have to be excluded
  # at attribution instead of once here.
  def self.record!(membership:, visitor_digest:, listing: nil, user: nil, now: Time.current)
    return nil unless membership.earning?

    existing = where(membership_id: membership.id, visitor_digest: visitor_digest)
               .where(expires_at: now..).newest_first.first
    return existing if existing && visitor_digest.present?

    create!(
      membership: membership,
      listing: listing,
      user: user,
      visitor_digest: visitor_digest,
      occurred_at: now,
      expires_at: now + membership.program.attribution_window
    )
  end

  # Never store the raw address. A digest is enough to tell two visitors apart
  # for dedupe and to spot one machine generating a suspicious number of clicks,
  # and it cannot be turned back into a person.
  def self.digest_for(ip, user_agent, salt: Rails.application.secret_key_base)
    return nil if ip.blank?

    OpenSSL::Digest::SHA256.hexdigest([ salt, ip, user_agent.to_s ].join("\n"))
  end
end
