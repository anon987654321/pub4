# frozen_string_literal: true

class Reaction < ApplicationRecord
  # Engine-ized Shared (tranche10)
  include Shared::ActivityTrackable
  tracks_activity created: "ReactionCreated", source_vertical: "social"
  include Shared.concern(:Notifiable) rescue nil

  KINDS = %w[like love laugh wow sad angry local].freeze

  belongs_to :user
  belongs_to :reactable, polymorphic: true, optional: true
  belongs_to :post, optional: true

  validates :kind, inclusion: { in: KINDS }, allow_blank: true
  validates :user_id, uniqueness: { scope: %i[reactable_type reactable_id post_id kind] }

  before_validation :backfill_reactable_from_post

  after_create_commit { broadcast_replace_later_to stream_name }
  after_destroy_commit { broadcast_replace_later_to stream_name }

  def target
    reactable || post
  end

  private

  def backfill_reactable_from_post
    self.reactable ||= post if post
    self.kind = "like" if kind.blank?
  end

  def stream_name
    target ? "brgen:reactions:#{target.class.name}:#{target.id}" : "brgen:reactions"
  end
end
