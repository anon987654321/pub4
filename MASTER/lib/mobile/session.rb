# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "time"

module Master
  module Mobile
    # The last forty turns between the phone and MASTER, so a face that
    # reconnects picks the conversation up. It is continuity, not a mission
    # store: missions stay where MASTER_MISSION_PATH puts them.
    class Session
      KEEP = 40
      RECENT = 8

      def initialize(root:)
        @path = File.join(File.expand_path(root), ".master", "mobile", "session.json")
        @data = load
      end

      def id = @data["id"]

      def append_turn!(role:, text:)
        @data["turns"] = (Array(@data["turns"]) << { "at" => now, "role" => role.to_s, "text" => text.to_s[0, 4000] })
                         .last(KEEP)
        save!
      end

      def context_blob
        Array(@data["turns"]).last(RECENT).map { |turn| "#{turn['role']}: #{turn['text']}" }.join("\n")
      end

      def touch!
        @data["last_seen_at"] = now
        save!
      end

      private

      def now = Time.now.utc.iso8601

      def load
        File.file?(@path) ? JSON.parse(File.read(@path)) : fresh
      rescue JSON::ParserError
        fresh
      end

      def fresh = { "id" => SecureRandom.uuid, "created_at" => now, "turns" => [] }

      def save!
        FileUtils.mkdir_p(File.dirname(@path))
        temp = "#{@path}.#{Process.pid}.tmp"
        File.write(temp, "#{JSON.pretty_generate(@data)}\n", perm: 0o600)
        File.rename(temp, @path)
      end
    end
  end
end
