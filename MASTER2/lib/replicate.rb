# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "result"
require_relative "replicate/models"
require_relative "replicate/client"
require_relative "replicate/generators"

module MASTER
  # Replicate - Image generation via Replicate API
  module Replicate
    extend self
    extend Models
    extend Client
    extend Generators

    TOKEN_NOT_SET = "REPLICATE_API_TOKEN not set."
    def api_key
      ENV["REPLICATE_API_TOKEN"] || ENV["REPLICATE_API_KEY"]
    end

    def available?
      !api_key.nil? && !api_key.empty?
    end
  end
end
