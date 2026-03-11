# frozen_string_literal: true

require "yaml"

module Master3
  module Routing
    class ContinuityIndex
      def initialize(root: Master3::ROOT)
        @root       = root
        @data_cache = nil
        @data_mtime = nil
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
        path = File.join(@root, "data", "continuity_models.yml")
        current_mtime = File.exist?(path) ? File.mtime(path) : nil

        if @data_cache.nil? || current_mtime != @data_mtime
          @data_cache = begin
            YAML.safe_load_file(path) || {}
          rescue StandardError
            {}
          end
          @data_mtime = current_mtime
        end

        @data_cache
      end
    end
  end
end
