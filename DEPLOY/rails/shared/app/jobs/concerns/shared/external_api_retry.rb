# frozen_string_literal: true
# AN309: Job retries with exponential backoff

module Shared
  module ExternalApiRetry
    extend ActiveSupport::Concern

    included do
      retry_on StandardError, wait: :polynomially_longer, attempts: 3
      retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 10.seconds, attempts: 3
    end
  end
end