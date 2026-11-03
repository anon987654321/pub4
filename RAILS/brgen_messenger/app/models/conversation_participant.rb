# frozen_string_literal: true

class ConversationParticipant < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  # IRC modes. RANK orders the roster (ops first) and lets join! only ever raise
  # a role, never demote a bot that re-joins.
  ROLES = %w[member voice op].freeze
  RANK = { "member" => 0, "voice" => 1, "op" => 2 }.freeze
  PREFIX = { "op" => "@", "voice" => "+", "member" => "" }.freeze

  validates :role, inclusion: { in: ROLES }
  # Backs the unique index rather than replacing it: a validation reads the same
  # stale row the finder did, so it cannot win a race. It is here so a duplicate
  # arrives as an error on the record instead of a RecordNotUnique from the
  # adapter, and so the constraint is visible from the model.
  validates :user_id, uniqueness: { scope: :conversation_id }

  # A pin is the viewer's own ordering of their inbox, which is why it lives
  # here rather than on the conversation both sides share.
  scope :pinned, -> { where.not(pinned_at: nil) }

  def pinned? = pinned_at.present?

  # Mute silences push and the badge; archive takes the thread out of the list.
  # Both are the viewer's own handling of their inbox, and both are timestamps
  # for the reason pinned_at is.
  scope :muted, -> { where.not(muted_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def muted? = muted_at.present?
  def archived? = archived_at.present?

  # Reading a thread, muting it or pinning it changes this person's row and
  # badge and nobody else's, so only their inbox is redrawn (InboxBroadcastJob).
  after_update_commit :refresh_inbox, if: :inbox_row_changed?

  def refresh_inbox = InboxBroadcastJob.perform_later(conversation_id, [ user_id ])

  def inbox_row_changed?
    saved_change_to_last_read_at? || saved_change_to_muted_at? || saved_change_to_pinned_at?
  end

  # Ops, then voices, then members; stable by id within a tier.
  scope :by_rank, lambda {
    order(Arel.sql("CASE role WHEN 'op' THEN 0 WHEN 'voice' THEN 1 ELSE 2 END"), :id)
  }

  def op? = role == "op"
  def voice? = role == "voice"
  def mode_prefix = PREFIX.fetch(role, "")
end
