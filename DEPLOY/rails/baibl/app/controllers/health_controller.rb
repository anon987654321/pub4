# frozen_string_literal: true

class HealthController < ActionController::Base
  def show
    checks = {
      database: database_ok?,
      solid_cache: cache_ok?,
      solid_queue: queue_ok?
    }
    healthy = checks.values.all?
    render json: { status: healthy ? "ok" : "degraded", checks: checks },
           status: healthy ? :ok : :service_unavailable
  end

  private

  def database_ok?
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue StandardError
    false
  end

  def cache_ok?
    Rails.cache.write("health_check", "ok", expires_in: 1.second)
    Rails.cache.read("health_check") == "ok"
  rescue StandardError
    false
  end

  def queue_ok?
    SolidQueue::Job.connection.execute("SELECT 1")
    true
  rescue StandardError
    false
  end
end