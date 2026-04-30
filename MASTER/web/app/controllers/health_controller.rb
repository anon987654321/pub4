# frozen_string_literal: true

class HealthController < ActionController::API
  def show
    render json: { status: "ok" }, status: :ok
  end
end
