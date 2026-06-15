# frozen_string_literal: true

require "json"

module Master
  module Trace
    # CD02: session replay — re-run a past turn from saved session.
    class SessionReplay
      def initialize(root:, session:)
        @root = root
        @session = session
      end

      def replay(session_id)
        path = File.join(@root, ".master", "sessions", "#{session_id}.json")
        return Result.err("session not found: #{session_id}") unless File.exist?(path)
        data = JSON.parse(File.read(path))
        turns = Array(data["messages"] || data["turns"])
        return Result.err("session empty") if turns.empty?
        last_user = turns.reverse.find { |t| t["role"] == "user" || t[:role] == "user" }
        return Result.err("no user turn in session") unless last_user
        content = last_user["content"] || last_user[:content]
        @session.restore_from!(data) if @session.respond_to?(:restore_from!)
        Result.ok(content.to_s)
      rescue StandardError => e
        Result.err("replay failed: #{e.message}")
      end
    end
  end
end