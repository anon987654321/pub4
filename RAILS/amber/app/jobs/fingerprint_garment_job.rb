# frozen_string_literal: true

# Stores a local CRC fingerprint for change-detection — not a semantic embedding.
# Real fashion embeddings (OpenRouter / pgvector) remain planned.
class FingerprintGarmentJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    # Both associations preloaded: strict_loading_by_default made the bare find
    # raise on item.user before this job ever wrote a fingerprint.
    item = Item.includes(:user, :garment_embedding).find(item_id)
    vector = WardrobeAi.new(item.user).fingerprint_for(item)
    return if vector.blank?

    item.create_garment_embedding! unless item.garment_embedding
    item.garment_embedding.update!(
      provider: "local",
      model: "crc32-fingerprint-64",
      dimensions: vector.length,
      vector: vector,
      metadata: {
        kind: "fingerprint_not_embedding",
        text: item.embedding_text,
        fingerprinted_at: Time.current.iso8601
      }
    )
  end
end
