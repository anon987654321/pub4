# frozen_string_literal: true

module Shared
  class SearchAnalytics
    def self.log(query:, result_count:, latency_ms:, vertical: nil, filters: {}, actor: nil, app: nil, locality: nil)
      new(
        query: query,
        result_count: result_count,
        latency_ms: latency_ms,
        vertical: vertical,
        filters: filters,
        actor: actor,
        app: app,
        locality: locality
      ).log
    end

    def initialize(query:, result_count:, latency_ms:, vertical: nil, filters: {}, actor: nil, app: nil, locality: nil)
      @query = query.to_s.strip
      @result_count = result_count.to_i
      @latency_ms = latency_ms.to_i
      @vertical = vertical
      @filters = filters
      @actor = actor
      @app = app || infer_app
      @locality = locality
    end

    def log
      return false if query.empty?

      Shared::EventEmitter.call(
        "SearchPerformed",
        actor: actor_payload,
        query: query,
        app: app,
        vertical: vertical,
        result_count: result_count,
        latency_ms: latency_ms,
        filters: filters,
        locality: locality
      )
    end

    private

    attr_reader :query, :result_count, :latency_ms, :vertical, :filters, :actor, :app, :locality

    def actor_payload
      return nil unless actor

      if actor.respond_to?(:id)
        { id: actor.id, type: actor.class.name }
      else
        actor
      end
    end

    def infer_app
      Rails.application.class.module_parent_name.underscore
    rescue StandardError
      "unknown"
    end
  end
end