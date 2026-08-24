# frozen_string_literal: true

class Reaction < ApplicationRecord
  # Engine-ized Shared (tranche10)
  tracks_activity created: "ReactionCreated", source_vertical: "social"
  include Shared::Notifiable

  KINDS = %w[like love laugh wow sad angry local].freeze

  belongs_to :user
  belongs_to :reactable, polymorphic: true, optional: true
  belongs_to :post, optional: true

  validates :kind, inclusion: { in: KINDS }, allow_blank: true
  validates :user_id, uniqueness: { scope: %i[reactable_type reactable_id post_id kind] }

  before_validation :backfill_reactable_from_post

  after_create_commit { broadcast_reaction_change }
  after_destroy_commit { broadcast_reaction_change }

  # Emoji, not the word "laugh". The kind stays the stored value; this is only
  # how it is drawn.
  GLYPHS = {
    "like" => "👍", "love" => "❤️", "laugh" => "😂",
    "wow" => "😮", "sad" => "😢", "angry" => "😠", "local" => "📍"
  }.freeze

  def self.glyph(kind) = GLYPHS.fetch(kind.to_s, "👍")

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

  # A message reaction rides the conversation's own stream.
  #
  # stream_name is per-target, which is right for a post — one page, one
  # subscription. A chat room renders 50+ messages, so per-target streams would
  # mean 50+ Turbo subscriptions per reader just so a thumbs-up can appear. The
  # room is already subscribed to its conversation, so reuse it: one extra
  # broadcast, no extra subscriptions, and reactions land live for everyone in
  # the room rather than only for people who happen to have that message open.
  #
  # A generic per-target broadcast to stream_name used to run first in this method
  # and was missing all three of the things it needed: a partial (the implicit
  # to_partial_path resolved to reactions/_reaction, which does not exist), a target,
  # and a subscriber — nothing anywhere subscribes to "brgen:reactions:…". Every
  # reaction and un-reaction enqueued a job that raised MissingTemplate into a stream
  # with no listener. Reviving it means subscribing wherever shared/_reaction_bar
  # renders, which is the 50+ subscriptions the paragraph above rules out.
  def broadcast_reaction_change
    msg = target
    return unless msg.is_a?(Message) && msg.conversation

    Turbo::StreamsChannel.broadcast_replace_to(
      msg.conversation,
      target: "reactions_#{ActionView::RecordIdentifier.dom_id(msg)}",
      partial: "messages/reactions",
      locals: { message: msg }
    )
  end
end
