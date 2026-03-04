# frozen_string_literal: true

module Bridges
  class Postpro
    DEFAULT_TIMEOUT_SECONDS = 5
    MAX_RETRIES = 3

    def initialize(client:, timeout: DEFAULT_TIMEOUT_SECONDS, retries: MAX_RETRIES)
      @client = client
      @timeout = timeout
      @retries = retries
    end

    def process(payload, enabled: true)
      return nil unless enabled
      return nil if payload.nil? || payload.to_s.strip.empty?

      with_retries do
        @client.post(
          "/postpro",
          payload: payload,
          timeout: @timeout
        )
      end
    end

    private

    def with_retries
      attempts = 0

      begin
        yield
      rescue StandardError => e
        attempts += 1
        raise if attempts > @retries

        raise e
      end
    end
  end
end