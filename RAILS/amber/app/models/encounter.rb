# frozen_string_literal: true

# One random-pairing ask, Chatroulette-style. Both sides asked for a stranger,
# so a pairing accepts itself: the posted row becomes either a wait or a match,
# and the match opens a message thread between the two askers under an accepted
# connection. The rows are short-lived bookkeeping, not history - the thread is
# where anything said lives.
class Encounter < ApplicationRecord
  WAITING = "waiting"
  MATCHED = "matched"
  CLOSED = "closed"
  STATUSES = [WAITING, MATCHED, CLOSED].freeze

  # A wait older than this is nobody waiting anymore; the next ask closes it.
  WAIT_LASTS_FOR = 90.seconds
  # A fresh match still walks its asker off the waiting page; an old one must
  # not yank a reader back into a thread they already left.
  MATCH_REMEMBERED_FOR = 2.minutes

  belongs_to :user
  belongs_to :partner, class_name: "User", optional: true

  scope :waiting, -> { where(status: WAITING) }
  scope :matched, -> { where(status: MATCHED) }
  scope :stale, -> { waiting.where(created_at: ...WAIT_LASTS_FOR.ago) }

  validates :status, inclusion: { in: STATUSES }

  def close! = update!(status: CLOSED)
  def fresh? = updated_at > MATCH_REMEMBERED_FOR.ago
  def waiting? = status == WAITING
  def matched? = status == MATCHED
  def closed? = status == CLOSED

  # Post an ask: pair with the oldest live wait from someone else, or wait.
  # One live wait per person - a second ask abandons the first. The lock
  # serializes two simultaneous asks so one waiting row cannot pair twice.
  def self.pair!(user)
    stale.update_all(status: CLOSED)
    user.encounters.waiting.update_all(status: CLOSED)

    transaction do
      other = waiting.includes(:user).where.not(user_id: user.id).order(:created_at).limit(1).lock.first
      if other
        match = create!(user: user, status: MATCHED, partner_id: other.user_id)
        other.update!(status: MATCHED, partner_id: user.id)
        accept_connection!(user, other.user)
        match
      else
        create!(user: user)
      end
    end
  end

  # Both sides asked for a stranger at the same moment, so the connection the
  # pairing needs arrives accepted - even upgrading a pending request between
  # the two, because consent here is mutual by construction.
  def self.accept_connection!(a, b)
    connection = Connection.find_by(requester: a, addressee: b) ||
                 Connection.find_by(requester: b, addressee: a) ||
                 Connection.new(requester: a, addressee: b)
    connection.status = "accepted"
    connection.save!
    connection
  end
end
