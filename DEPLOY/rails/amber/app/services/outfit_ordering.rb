# frozen_string_literal: true

class OutfitOrdering
  def self.call(outfit, ordered_ids)
    new(outfit, ordered_ids).call
  end

  def initialize(outfit, ordered_ids)
    @outfit = outfit
    @ordered_ids = Array(ordered_ids).map(&:to_s)
  end

  def call
    items = outfit.outfit_items.where(id: ordered_ids)
    index = ordered_ids.each_with_index.to_h

    items.find_each do |outfit_item|
      outfit_item.update!(position: index.fetch(outfit_item.id.to_s, outfit_item.position))
    end

    Shared::EventEmitter.call("amber.outfit.reordered", outfit_id: outfit.id, count: ordered_ids.size) if defined?(Shared::EventEmitter)
    outfit.outfit_items.order(:position)
  end

  private

  attr_reader :outfit, :ordered_ids
end
