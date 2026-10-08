# frozen_string_literal: true

# Stores a local CRC fingerprint for change-detection — not a semantic embedding.
# Real fashion embeddings (OpenRouter / pgvector) remain planned.
class FingerprintGarmentJob < ApplicationJob
  queue_as :default

  # A second fingerprint for an item already waiting would write the same row.
  limits_concurrency to: 1, key: ->(item_id) { item_id }, duration: 2.hours, on_conflict: :discard

  def perform(item_id)
    # Both associations preloaded: strict_loading_by_default made the bare find
    # raise on item.user before this job ever wrote a fingerprint.
    item = Item.includes(:user, :garment_embedding).find(item_id)
    vector = WardrobeAi.new(item.user).fingerprint_for(item)
    return if vector.blank?

    # One write with the attributes, not an empty create followed by an update.
    # GarmentEmbedding requires provider and model, so `create_garment_embedding!`
    # with no arguments raised RecordInvalid before the update could supply
    # them — this job has never stored a fingerprint for an item that did not
    # already have an embedding row, which is every item the first time.
    attributes = {
      provider: "local",
      model: "crc32-fingerprint-64",
      dimensions: vector.length,
      vector: vector,
      metadata: {
        kind: "fingerprint_not_embedding",
        text: item.embedding_text,
        fingerprinted_at: Time.current.iso8601
      }
    }
    embedding = item.garment_embedding
    embedding ? embedding.update!(attributes) : item.create_garment_embedding!(attributes)
  end
end
