# frozen_string_literal: true

class FleetHealthController < ActionController::API
  def show
    checks = {
      database: database_ok?,
      cache: cache_ok?,
      queue: queue_ok?,
      cable: cable_ok?,
    }
    critical = %i[database]
    critical_ok = critical.all? { |key| checks[key] }
    status = critical_ok ? (checks.values.all? ? "ok" : "degraded") : "unavailable"
    http = critical_ok ? :ok : :service_unavailable
    render json: { status:, app: Rails.application.class.module_parent_name.to_s, checks: }, status: http
  end

  private

  # A query, not connection.active?. An adapter connects lazily, so active? is
  # nil in a worker that has not queried yet, and an idle worker answered 503
  # over a database that was fine.
  def database_ok?
    ActiveRecord::Base.connection.select_value("SELECT 1").to_i == 1
  rescue StandardError
    false
  end

  # A round trip of a value nobody else writes, through whatever store the app
  # runs. A fixed "1" can be read back from an earlier probe after writes stop
  # landing, and a store that drops every write passed because it was not
  # Solid Cache.
  def cache_ok?
    token = SecureRandom.hex(8)
    Rails.cache.write("_fleet_health_probe", token, expires_in: 10)
    Rails.cache.read("_fleet_health_probe") == token
  rescue StandardError
    false
  end

  def queue_ok?
    return true unless defined?(SolidQueue::Job)

    SolidQueue::Job.limit(1).pick(:id)
    true
  rescue StandardError
    false
  end

  def cable_ok?
    return true unless defined?(SolidCable::Message)

    SolidCable::Message.limit(1).pick(:id)
    true
  rescue StandardError
    false
  end
end
