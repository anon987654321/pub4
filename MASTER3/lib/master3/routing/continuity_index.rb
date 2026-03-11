# frozen_string_literal: true

require "yaml"

module Master3
  module Routing
    class ContinuityIndex
      def initialize(root: Master3::ROOT)
        @root = root
      end

      def fallback_models
        return [] unless enabled?

        [openrouter_latest, replicate_latest, ferrum_latest].flatten.compact.uniq
      end

      private

      def enabled?
        data.dig("continuity", "enabled") != false
      end

      def openrouter_latest
        data.dig("continuity", "openrouter", "free_latest").to_a
      end

      def replicate_latest
        data.dig("continuity", "replicate", "free_latest").to_a
      end

      def ferrum_latest
        data.dig("continuity", "ferrum_web_chat", "free_latest").to_a
      end

      def data
        @data ||= begin
          path = File.join(@root, "data", "continuity_models.yml")
          YAML.safe_load_file(path) || {}
        rescue StandardError
          {}
        end
      end
    end
  end
end
