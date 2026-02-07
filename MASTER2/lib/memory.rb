# frozen_string_literal: true

require "json"
require "fileutils"

module MASTER
  module Memory
    HISTORY_THRESHOLD = 10
    HISTORY_HEAD = 2
    HISTORY_TAIL = 8

    @sessions = {}

    class << self
      def store(key, value)
        @sessions[key] = value
      end

      def fetch(key)
        @sessions[key]
      end

      def clear
        @sessions.clear
      end

      def all
        @sessions.dup
      end

      def size
        @sessions.size
      end

      # Compress history to fit token limits
      def compress(history, max_tokens: 4000)
        return history if history.size <= HISTORY_THRESHOLD
        history.first(HISTORY_HEAD) + history.last(HISTORY_TAIL)
      end

      # Persist session to disk
      def save_session(session_id, data)
        path = File.join(Paths.sessions, "#{session_id}.json")
        File.write(path, JSON.pretty_generate(data))
        path
      end

      # Load session from disk
      def load_session(session_id)
        path = File.join(Paths.sessions, "#{session_id}.json")
        return nil unless File.exist?(path)
        JSON.parse(File.read(path), symbolize_names: true)
      end

      # List all saved sessions
      def list_sessions
        Dir.glob(File.join(Paths.sessions, "*.json")).map do |f|
          File.basename(f, ".json")
        end
      end

      # Delete old sessions
      def prune_sessions(max_age_hours: 24)
        cutoff = Time.now - (max_age_hours * 3600)
        Dir.glob(File.join(Paths.sessions, "*.json")).each do |f|
          File.delete(f) if File.mtime(f) < cutoff
        end
      end
    end
  end
end
