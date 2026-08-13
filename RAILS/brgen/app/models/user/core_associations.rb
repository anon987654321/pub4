# frozen_string_literal: true

class User
  module CoreAssociations
    extend ActiveSupport::Concern

    included do
      has_many :account_merges, dependent: :destroy
      has_many :activity_events, foreign_key: :actor_id, dependent: :nullify
      has_many :comments, dependent: :destroy
      has_many :communities
      has_many :conversation_participants, dependent: :destroy
      has_many :conversations, through: :conversation_participants
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
    end
  end
end
