# frozen_string_literal: true

require "yaml"
require "fileutils"
require "time"

module Master
  module Mobile
    # What the person on the phone has asked to be called, and other plain
    # preferences, kept at MASTER_MEMORY_PATH. Each change is logged; the
    # newest two hundred are kept. Preferences never reach soul.yml or laws.yml.
    class Personality
      LOG_LIMIT = 200

      def initialize(root:, path: ENV["MASTER_MEMORY_PATH"] || ".master/mobile/memory.yml")
        @path = File.expand_path(path, File.expand_path(root))
        @data = load
      end

      def preferences = @data.fetch("preferences", {})

      def remember!(key, value)
        (@data["preferences"] ||= {})[key.to_s] = value.to_s
        entry = { "at" => Time.now.utc.iso8601, "key" => key.to_s, "value" => value.to_s }
        @data["log"] = (Array(@data["log"]) << entry).last(LOG_LIMIT)
        save!
        value.to_s
      end

      def context_snippet(max_keys: 12)
        return "" if preferences.empty?

        lines = preferences.first(max_keys).map { |key, value| "- #{key}: #{value}" }
        "User preferences (mobile):\n#{lines.join("\n")}"
      end

      private

      def load
        File.file?(@path) ? (YAML.safe_load_file(@path) || blank) : blank
      rescue Psych::Exception
        blank
      end

      def blank = { "schema" => 1, "preferences" => {}, "log" => [] }

      def save!
        FileUtils.mkdir_p(File.dirname(@path))
        temp = "#{@path}.#{Process.pid}.tmp"
        File.write(temp, YAML.dump(@data))
        File.rename(temp, @path)
      end
    end
  end
end
