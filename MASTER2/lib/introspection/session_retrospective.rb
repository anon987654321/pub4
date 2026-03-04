# frozen_string_literal: true

require "json"

module Introspection
  class SessionRetrospective
    RETROSPECTIVE_FILE_PREFIX = "session_retrospective_"
    RETROSPECTIVE_FILE_SUFFIX = ".json"

    def initialize(session:, storage: Paths, logger: Logging)
      @session = session
      @storage = storage
      @logger = logger
    end

    def run
      session_id = @session&.id
      return nil if session_id.nil?

      cached = load_retrospective(session_id)
      return cached unless cached.nil?

      generated = build_retrospective(session_id)
      persist_retrospective(session_id, generated)
      generated
    end

    def load_retrospective(session_id)
      json_text = read_retrospective_file(session_id)
      return nil if json_text.nil? || json_text.strip.empty?

      parse_retrospective_json(session_id, json_text)
    end

    def persist_retrospective(session_id, retrospective_hash)
      file_path = retrospective_file_path(session_id)
      File.write(file_path, JSON.pretty_generate(retrospective_hash))
      true
    rescue StandardError => e
      @logger.warn("Failed to persist session retrospective for session_id=#{session_id} path=#{file_path}: #{e.class}: #{e.message}")
      nil
    end

    private

    def retrospective_file_path(session_id)
      @storage.data_file("#{RETROSPECTIVE_FILE_PREFIX}#{session_id}#{RETROSPECTIVE_FILE_SUFFIX}")
    end

    def read_retrospective_file(session_id)
      file_path = retrospective_file_path(session_id)
      return nil unless File.exist?(file_path)

      File.read(file_path)
    rescue StandardError => e
      @logger.warn("Failed to read session retrospective for session_id=#{session_id} path=#{file_path}: #{e.class}: #{e.message}")
      nil
    end

    def parse_retrospective_json(session_id, json_text)
      JSON.parse(json_text)
    rescue StandardError => e
      @logger.warn("Failed to parse session retrospective JSON for session_id=#{session_id}: #{e.class}: #{e.message}")
      nil
    end

    def build_retrospective(session_id)
      {
        "session_id" => session_id,
        "generated_at" => Time.now.utc.iso8601,
        "events_count" => safe_events_count,
        "notes" => safe_session_notes
      }
    end

    def safe_events_count
      @session.respond_to?(:events) ? Array(@session.events).size : 0
    rescue StandardError => e
      @logger.warn("Failed to compute events_count for session_id=#{@session&.id}: #{e.class}: #{e.message}")
      0
    end

    def safe_session_notes
      return @session.notes if @session.respond_to?(:notes)

      nil
    rescue StandardError => e
      @logger.warn("Failed to read session notes for session_id=#{@session&.id}: #{e.class}: #{e.message}")
      nil
    end
  end
end