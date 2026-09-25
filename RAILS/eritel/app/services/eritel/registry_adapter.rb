# frozen_string_literal: true

module Eritel
  class RegistryAdapter
    class UnsupportedOperation < StandardError; end

    def initialize(endpoint: nil, credentials: nil)
      @endpoint = endpoint
      @credentials = credentials
    end

    def check(domain)
      raise UnsupportedOperation, "registry check is not configured"
    end

    def create(domain:, registrant:)
      raise UnsupportedOperation, "registry writes are not configured"
    end

    def renew(domain:, years:)
      raise UnsupportedOperation, "registry writes are not configured"
    end

    def delete(domain:)
      raise UnsupportedOperation, "registry writes are not configured"
    end

    private

    attr_reader :endpoint, :credentials
  end
end
