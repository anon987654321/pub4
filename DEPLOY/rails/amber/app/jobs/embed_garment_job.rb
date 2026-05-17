class EmbedGarmentJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find(item_id)
    vector = WardrobeAiService.new(item.user).embedding_for(item)
    return if vector.blank?

    item.create_garment_embedding! unless item.garment_embedding
    item.garment_embedding.update!(
      provider: "openrouter",
      model: WardrobeAiService::MODEL,
      dimensions: vector.length,
      vector: vector,
      metadata: { text: item.embedding_text, embedded_at: Time.current.iso8601 }
    )
  end
end
