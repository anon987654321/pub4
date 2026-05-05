# frozen_string_literal: true

# Pre-define Bedrock constants before ruby_llm loads.
# Zeitwerk skips autoloading already-defined constants, so bedrock/auth.rb
# (which requires openssl.so) is never touched.
# MASTER uses OpenRouter exclusively — Bedrock is never needed.
module RubyLLM
  module Providers
    class Bedrock
      module Auth
        def self.included(_base); end
      end

      def self.api_base = ""
      def self.headers(_cfg) = {}
      def self.models = []
      def self.slug = "bedrock"
    end
  end
end
