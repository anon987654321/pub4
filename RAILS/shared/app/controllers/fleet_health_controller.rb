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

  def database_ok?
    ActiveRecord::Base.connection.active?
  rescue StandardError
    false
  end

  def cache_ok?
    return true unless Rails.cache.is_a?(ActiveSupport::Cache::SolidCacheStore) || defined?(SolidCache::Entry)

    Rails.cache.write("_fleet_health_probe", "1", expires_in: 10)
    Rails.cache.read("_fleet_health_probe") == "1"
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
