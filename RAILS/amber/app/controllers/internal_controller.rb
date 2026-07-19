# frozen_string_literal: true

class InternalController < ApplicationController
  include Shared::InternalTokenAuth

  def status
    render json: {
      app: "amber",
      generated_at: Time.now.utc.iso8601,
      items: Item.count,
      outfits: Outfit.count,
      users: User.count,
      wardrobe_items: (defined?(WardrobeItem) ? WardrobeItem.count : 0),
      master_client: Shared::MasterClient.configured?
    }
  end
end
