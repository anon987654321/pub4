# frozen_string_literal: true

# One random-pairing ask, Chatroulette-style, on the messenger's own
# machinery. Both sides asked for a stranger, so the pairing accepts itself:
# the posted row becomes either a wait or a match, and the match opens a
# direct conversation between the two askers. The rows are short-lived
# bookkeeping, not history - the conversation is where anything said lives.
class Encounter < ApplicationRecord
  WAITING = "waiting"
  MATCHED = "matched"
  CLOSED = "closed"
  STATUSES = [WAITING, MATCHED, CLOSED].freeze

  # A wait older than this is nobody waiting anymore; the next ask closes it.
  WAIT_LASTS_FOR = 90.seconds
  # A fresh match still walks its asker off the waiting page; an old one must
  # not yank a reader back into a conversation they already left.
  MATCH_REMEMBERED_FOR = 2.minutes

  belongs_to :user
  belongs_to :partner, class_name: "User", optional: true
  belongs_to :conversation, optional: true

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
  # People either side has blocked never pair, exactly as nearby's stranger
  # chats refuse them.
  def self.pair!(user, blocked_ids: [])
    stale.update_all(status: CLOSED)
    user.encounters.waiting.update_all(status: CLOSED)

    transaction do
      candidates = waiting.includes(:user).where.not(user_id: user.id)
      candidates = candidates.where.not(user_id: blocked_ids) if blocked_ids.any?
      other = candidates.order(:created_at).limit(1).lock.first
      if other
        conversation = Conversation.find_or_create_direct(user, other.user)
        match = create!(user: user, status: MATCHED, partner_id: other.user_id,
                        conversation_id: conversation.id)
        other.update!(status: MATCHED, partner_id: user.id, conversation_id: conversation.id)
        match
      else
        create!(user: user)
      end
    end
  end
end
