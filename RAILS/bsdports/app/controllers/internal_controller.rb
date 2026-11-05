# frozen_string_literal: true

class InternalController < ApplicationController
  include Shared::InternalTokenAuth
  include Shared::BuildInfoHelper

  # What this process is running. The deploy stamp proves what a deploy
  # wrote; this says what the serving process booted — the pair an operator
  # compares when a health check and the last deploy disagree.
  def version
    render json: {
      app: "bsdports",
      revision: app_revision,
      generated_at: Time.now.utc.iso8601,
    }
  end

  def status
    render json: {
      app: "bsdports",
      generated_at: Time.now.utc.iso8601,
      ports: Port.count,
      categories: Category.count,
      platforms: Platform.count,
      advisories: (defined?(SecurityAdvisory) ? SecurityAdvisory.count : 0),
      master_client: Contracts::MasterClient.configured?
    }
  end
end
