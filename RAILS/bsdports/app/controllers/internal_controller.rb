# frozen_string_literal: true

class InternalController < ApplicationController
  include Shared::InternalTokenAuth

  def status
    render json: {
      app: "bsdports",
      generated_at: Time.now.utc.iso8601,
      ports: Port.count,
      categories: Category.count,
      platforms: Platform.count,
      advisories: (defined?(SecurityAdvisory) ? SecurityAdvisory.count : 0),
      master_client: Shared::MasterClient.configured?
    }
  end
end
