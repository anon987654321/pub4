# frozen_string_literal: true

class InternalController < ApplicationController
  include Shared::InternalTokenAuth
  include Shared::BuildInfoHelper

  # What this process is running. The deploy stamp proves what a deploy
  # wrote; this says what the serving process booted — the pair an operator
  # compares when a health check and the last deploy disagree.
  def version
    render json: {
      app: "amber",
      revision: app_revision,
      generated_at: Time.now.utc.iso8601,
    }
  end

  def status
    render json: {
      app: "amber",
      generated_at: Time.now.utc.iso8601,
      items: Item.count,
      outfits: Outfit.count,
      users: User.count,
      wardrobe_items: (defined?(WardrobeItem) ? WardrobeItem.count : 0),
      master_client: Contracts::MasterClient.configured?,
    }
  end
end
