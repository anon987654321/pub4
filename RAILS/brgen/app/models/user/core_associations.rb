# frozen_string_literal: true

class User
  module CoreAssociations
    extend ActiveSupport::Concern

    included do
      has_many :account_merges, dependent: :destroy
      has_many :activity_events, foreign_key: :actor_id, dependent: :nullify, inverse_of: :actor
      has_many :comments, dependent: :destroy
      has_many :communities
      has_many :conversation_participants, dependent: :destroy
      has_many :conversations, through: :conversation_participants
      # message_receipts and typing_indicators both carry an FK to users and were
      # declared only on Message and Conversation, never here — so destroying a
      # user who had ever been in a conversation raised
      # SQLite3::ConstraintException: FOREIGN KEY constraint failed, from the
      # database rather than from Rails, with no association in the model to
      # explain it.
      #
      # That made account deletion impossible for any user with chat history —
      # the users table carries deletion_scheduled_at and deleted_at for exactly
      # that flow — and it is why PruneGuestUsersJob had never removed a row.
      # Measured 2026-08-13: guests owned 194,295 message_receipts, and the prune
      # died on the first batch that contained one.
      has_many :message_receipts, dependent: :destroy
      has_many :typing_indicators, dependent: :destroy
      has_many :external_identities, dependent: :destroy
      has_many :identity_assurances, dependent: :destroy
      has_many :moderation_flags, dependent: :destroy
      has_many :moderation_reports, dependent: :destroy
      has_many :notifications, dependent: :destroy
      has_many :posts, dependent: :destroy
      has_many :push_subscriptions, dependent: :destroy
      has_many :reputation_scores, dependent: :destroy
      has_many :sessions, dependent: :destroy
      has_many :trust_signals, dependent: :destroy
      has_many :votes, dependent: :destroy
      has_many :reposts, dependent: :destroy
      has_many :reposted_posts, through: :reposts, source: :post
      has_many :events, dependent: :destroy
      has_many :event_rsvps, dependent: :destroy
      has_many :attending_events, through: :event_rsvps, source: :event
      has_many :stories, dependent: :destroy
      has_many :story_views, dependent: :destroy
    end
  end
end
