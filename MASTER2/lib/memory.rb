# frozen_string_literal: true

require "json"
require "fileutils"

module MASTER
  # Memory - Session cache and persistence
  module Memory
    COMPRESS_AFTER_MESSAGES = 10  # Fixed: was 11, should be 10
    KEEP_FIRST_N = 2
    KEEP_LAST_N = 8

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
        return history if history.size <= COMPRESS_AFTER_MESSAGES
        history.first(KEEP_FIRST_N) + history.last(KEEP_LAST_N)
      end

      def save_session(session_id, data)
        path = Paths.session_file(session_id)
        File.write(path, JSON.pretty_generate(data))
        path
      end

      def load_session(session_id)
        path = Paths.session_file(session_id)
        return nil unless File.exist?(path)

        JSON.parse(File.read(path), symbolize_names: true)
      end

      def list_sessions
        Dir.glob(File.join(Paths.sessions, "*.json")).map { |f| File.basename(f, ".json") }
      end

      def delete_old_sessions(max_age_hours: 24)
        cutoff = Time.now - (max_age_hours * 3600)
        Dir.glob(File.join(Paths.sessions, "*.json")).each { |f| File.delete(f) if File.mtime(f) < cutoff }
      end

      # Search past sessions for relevant content
      def search(query, limit: 3)
        return [] if query.nil? || query.strip.empty?
        
        results = []
        query_words = query.downcase.split(/\s+/)
        
        list_sessions.each do |session_id|
          data = load_session(session_id)
          next unless data && data[:messages]
          
          data[:messages].each do |msg|
            content = msg[:content].to_s.downcase
            # Score by number of matching words
            score = query_words.count { |w| content.include?(w) }
            if score > 0
              results << { score: score, content: msg[:content][0..200], session: session_id }
            end
          end
        end
        
        results.sort_by { |r| -r[:score] }
               .first(limit)
               .map { |r| r[:content] }
      rescue StandardError
        []
      end
    end
  end
end
