# frozen_string_literal: true

require "digest"

module Shared
  # Cache-backed replay protection for queued browser mutations.
  #
  # This is intentionally opt-in at the request boundary only when the client
  # supplies X-Idempotency-Key. A successful response is replayed verbatim for
  # the same actor, path and key; a concurrent request with the same key is
  # rejected instead of running the mutation twice. Cache eviction remains a
  # documented limit, so durable exactly-once semantics still belong to a
  # database uniqueness constraint on operations that require them.
  module Idempotency
    extend ActiveSupport::Concern

    KEY_HEADER = "HTTP_X_IDEMPOTENCY_KEY"
    TTL = 24.hours
    LOCK_TTL = 10.minutes

    included do
      before_action :check_idempotency, if: :idempotency_request?
      after_action :store_idempotency_response, if: :idempotency_request?
    end

    private

    def idempotency_request?
      request.headers[KEY_HEADER].to_s.match?(/\A[0-9a-fA-F-]{16,128}\z/) &&
        %w[POST PUT PATCH DELETE].include?(request.request_method)
    end

    def idempotency_cache_key
      actor = Current.user&.id || "anonymous"
      digest = Digest::SHA256.hexdigest(
        [Rails.application.class.module_parent_name, actor, request.request_method, request.path,
         request.headers[KEY_HEADER]].join("\0")
      )
      "pub4:idempotency:v1:#{digest}"
    end

    def check_idempotency
      key = idempotency_cache_key
      cached = Rails.cache.read(key)
      if cached.is_a?(Hash) && cached["state"] == "complete"
        replay_idempotency_response(cached)
        return
      end

      claimed = Rails.cache.write(
        key,
        { "state" => "processing" },
        expires_in: LOCK_TTL,
        unless_exist: true
      )
      return if claimed

      # Another request may have completed between the read and the claim.
      cached = Rails.cache.read(key)
      if cached.is_a?(Hash) && cached["state"] == "complete"
        replay_idempotency_response(cached)
      else
        head :conflict
      end
    end

    def store_idempotency_response
      if response.status >= 500
        Rails.cache.delete(idempotency_cache_key)
        return
      end
      cached = Rails.cache.read(idempotency_cache_key)
      return if cached.is_a?(Hash) && cached["state"] == "complete"

      Rails.cache.write(
        idempotency_cache_key,
        {
          "state" => "complete",
          "status" => response.status,
          "body" => response.body.to_s,
          "content_type" => response.media_type,
          "location" => response.headers["Location"]
        },
        expires_in: TTL
      )
    rescue StandardError => error
      Rails.logger.warn("[idempotency] response cache failed: #{error.class}: #{error.message}")
    end

    def replay_idempotency_response(cached)
      self.status = cached["status"].to_i
      self.content_type = cached["content_type"].to_s if cached["content_type"].present?
      response.set_header("Location", cached["location"]) if cached["location"].present?
      self.response_body = cached["body"].to_s
    end
  end
end
