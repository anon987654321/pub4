# frozen_string_literal: true

module MASTER
  # Timeouts - Centralized timeout configuration
  # All timeouts can be overridden via environment variables
  module Timeouts
    # LLM request timeout (seconds)
    LLM_TIMEOUT = (ENV['MASTER_LLM_TIMEOUT'] || 60).to_i
    
    # Web request timeout (seconds)
    WEB_TIMEOUT = (ENV['MASTER_WEB_TIMEOUT'] || 30).to_i
    
    # Replicate API timeout for long-running generations (seconds)
    REPLICATE_TIMEOUT = (ENV['MASTER_REPLICATE_TIMEOUT'] || 300).to_i
    
    # Poll interval for async operations (seconds)
    POLL_INTERVAL = (ENV['MASTER_POLL_INTERVAL'] || 2).to_i
    
    # HTTP connection timeouts
    HTTP_OPEN_TIMEOUT = (ENV['MASTER_HTTP_OPEN_TIMEOUT'] || 10).to_i
    HTTP_READ_TIMEOUT = (ENV['MASTER_HTTP_READ_TIMEOUT'] || 60).to_i
  end
end
