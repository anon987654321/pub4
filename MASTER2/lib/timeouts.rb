# frozen_string_literal: true

require_relative 'llm'
require_relative 'replicate'

module MASTER
  # Timeouts - Backward compatibility module
  # Constants have been moved to their respective modules:
  # - LLM_TIMEOUT, WEB_TIMEOUT -> LLM module
  # - REPLICATE_TIMEOUT, POLL_INTERVAL, HTTP_OPEN_TIMEOUT, HTTP_READ_TIMEOUT -> Replicate module
  module Timeouts
    # Delegate to LLM module
    def self.const_missing(name)
      case name
      when :LLM_TIMEOUT, :WEB_TIMEOUT
        LLM.const_get(name)
      when :REPLICATE_TIMEOUT, :POLL_INTERVAL, :HTTP_OPEN_TIMEOUT, :HTTP_READ_TIMEOUT
        Replicate.const_get(name)
      else
        super
      end
    end

    # For direct access (backward compatibility)
    LLM_TIMEOUT = LLM::LLM_TIMEOUT
    WEB_TIMEOUT = LLM::WEB_TIMEOUT
    REPLICATE_TIMEOUT = Replicate::REPLICATE_TIMEOUT
    POLL_INTERVAL = Replicate::POLL_INTERVAL
    HTTP_OPEN_TIMEOUT = Replicate::HTTP_OPEN_TIMEOUT
    HTTP_READ_TIMEOUT = Replicate::HTTP_READ_TIMEOUT
  end
end
