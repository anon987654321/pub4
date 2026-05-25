# frozen_string_literal: true

module Rails
  class HealthController < ActionController::Base
    def show
      ActiveRecord::Base.connection.execute("SELECT 1")
      render json: { status: "OK", environment: Rails.env }, status: :ok
    rescue StandardError => e
      render json: { status: "CRITICAL", error: e.message }, status: :service_unavailable
    end
  end
end
