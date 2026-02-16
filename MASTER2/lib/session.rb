# frozen_string_literal: true

require "securerandom"
require "json"
require "time"
require "fileutils"

require_relative "session/memory"
require_relative "session/capture"
require_relative "session/replay"
require_relative "session/language"
require_relative "session/persona"

module MASTER
  # Session - Persistent session management with auto-save
  # STORAGE: Uses Memory module (JSON files in .sessions/)
  # NOTE: DB JSONL system is separate and used by LearningFeedback
  # See learnings.rb line 241-242 for architecture notes
  class Session
    attr_reader :id, :created_at, :history, :metadata

    AUTOSAVE_INTERVAL = 30  # seconds

    def initialize(id: nil)
      @id = id || SecureRandom.uuid
      @created_at = Time.now.utc
      @history = []
      @metadata = {}
      @dirty = false
      @last_save = Time.now
    end

    def add(role:, content:, model: nil, cost: nil)
      entry = {
        role: role,
        content: content,
        model: model,
        cost: cost,
        timestamp: Time.now.utc.iso8601,
      }.compact

      @history << entry
      @dirty = true

      # Auto-save periodically
      autosave_if_needed
      entry
    end

    def add_user(content)
      add(role: :user, content: content)
    end

    def add_assistant(content, model: nil, cost: nil)
      add(role: :assistant, content: content, model: model, cost: cost)
    end

    def last_exchange
      return nil if @history.size < 2

      {
        user: @history[-2],
        assistant: @history[-1],
      }
    end

    def total_cost
      @history.sum { |h| h[:cost] || 0 }
    end

    def message_count
      @history.size
    end

    def context_for_llm(max_messages: 20)
      compressed = Memory.compress(@history)
      compressed.last(max_messages).map do |h|
        { role: h[:role].to_s, content: h[:content] }
      end
    end

    def write_metadata(key, value)
      @metadata[key.to_sym] = value
      @dirty = true
    end

    def metadata_value(key)
      @metadata[key.to_sym]
    end

    # Aliases for backward compatibility
    alias set_metadata write_metadata
    alias get_metadata metadata_value

    def dirty?
      @dirty
    end

    def autosave_if_needed
      return unless @dirty
      return if Time.now - @last_save < AUTOSAVE_INTERVAL
      save
    end

    def save
      return unless @dirty

      data = {
        id: @id,
        created_at: @created_at.iso8601,
        history: @history,
        metadata: @metadata,
      }

      Memory.save_session(@id, data)
      @dirty = false
      @last_save = Time.now
      true
    end

    class << self
      # @param id [String] Session ID
      # @return [Session, nil] Session instance or nil if not found
      def load(id)
        data = Memory.load_session(id)
        return nil unless data

        session = new(id: data[:id])
        session.instance_variable_set(:@created_at, Time.parse(data[:created_at]))
        session.instance_variable_set(:@history, data[:history] || [])
        session.instance_variable_set(:@metadata, data[:metadata] || {})
        session.instance_variable_set(:@dirty, false)
        session
      end

      # List all available sessions
      # @return [Array<Hash>] Array of session metadata
      def list
        Memory.list_sessions
      end

      # Get current session (creates new if none exists)
      # @return [Session] Current session
      def current
        @current ||= new
      end

      # Set current session
      # @param session [Session] Session to set as current
      def current=(session)
        @current = session
      end

      # Resume existing session by ID
      # @param id [String] Session ID to resume
      # @return [Session, nil] Session if found, nil otherwise
      def resume(id)
        session = load(id)
        return nil unless session

        @current = session
        session
      end

      # Start new session and set as current
      # @return [Session] New session
      def start_new
        @current = new
      end

      # Install signal handlers for crash recovery
      # @return [void]
      def install_crash_handlers
        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            save_on_crash
            exit(signal == "INT" ? 130 : 143)
          end
        end
      rescue ArgumentError
        # Some signals not available on all platforms
      end

      # Save current session on crash
      # @return [void]
      def save_on_crash
        return unless @current&.dirty?

        @current.instance_variable_set(:@metadata,
          @current.metadata.merge(crashed: true, crash_time: Time.now.utc.iso8601))
        @current.save
      rescue StandardError => e
        $stderr.puts "session: crash save failed: #{e.message}"
      end
    end

    def to_h
      {
        id: @id,
        created_at: @created_at.iso8601,
        messages: @history.size,
        cost: total_cost,
        metadata: @metadata,
      }
    end

    # Delegate language methods to Language module
    def self.detect_language(text)
      Language.detect_language(text)
    end

    def self.norwegian_style_check(text)
      Language.norwegian_style_check(text)
    end

    # Delegate persona methods to Persona module
    def self.set_persona(persona)
      Persona.set_persona(persona)
    end

    def self.current_persona
      Persona.current_persona
    end
  end
end
