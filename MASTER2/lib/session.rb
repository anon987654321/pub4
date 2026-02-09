# frozen_string_literal: true

require "securerandom"
require "json"
require "time"

module MASTER
  # Session - Persistent session management with auto-save
  class Session
    attr_reader :id, :created_at, :history, :metadata

    AUTOSAVE_INTERVAL = 30  # seconds
    SUPPORTED_LANGUAGES = %i[english norwegian].freeze
    SUPPORTED_PERSONAS = %i[ronin lawyer hacker architect sysadmin trader medic].freeze
    
    NORWEGIAN_RULES = [
      "Use bokmål, not nynorsk",
      "Prefer short sentences",
      "Avoid anglicisms when Norwegian words exist",
      "Match user's formality level"
    ].freeze

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

    def self.load(id)
      data = Memory.load_session(id)
      return nil unless data

      session = new(id: data[:id])
      session.instance_variable_set(:@created_at, Time.parse(data[:created_at]))
      session.instance_variable_set(:@history, data[:history] || [])
      session.instance_variable_set(:@metadata, data[:metadata] || {})
      session.instance_variable_set(:@dirty, false)
      session
    end

    def self.list
      Memory.list_sessions
    end

    def self.current
      @current ||= new
    end

    def self.current=(session)
      @current = session
    end

    def self.resume(id)
      session = load(id)
      return nil unless session

      @current = session
      session
    end

    def self.start_new
      @current = new
    end

    # Install signal handlers for crash recovery
    def self.install_crash_handlers
      %w[INT TERM].each do |signal|
        Signal.trap(signal) do
          save_on_crash
          exit(signal == "INT" ? 130 : 143)
        end
      end
    rescue ArgumentError
      # Some signals not available on all platforms
    end

    def self.save_on_crash
      return unless @current&.dirty?
      
      @current.instance_variable_set(:@metadata, 
        @current.metadata.merge(crashed: true, crash_time: Time.now.utc.iso8601))
      @current.save
    rescue StandardError
      # Best effort on crash
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

    # Language detection and multi-language support
    def self.detect_language(text)
      # Norwegian indicators
      norwegian_words = %w[og men er på av til fra med som den det]
      norwegian_count = norwegian_words.count { |word| text.downcase.include?(word) }
      
      # English indicators
      english_words = %w[the and but are on of to from with as that this]
      english_count = english_words.count { |word| text.downcase.include?(word) }
      
      if norwegian_count > english_count
        Result.ok(language: :norwegian, confidence: norwegian_count.to_f / (norwegian_count + english_count))
      else
        Result.ok(language: :english, confidence: english_count.to_f / (norwegian_count + english_count))
      end
    end

    def self.norwegian_style_check(text)
      issues = []
      
      # Check for common anglicisms
      anglicisms = {
        "meeting" => "møte",
        "deal" => "avtale",
        "deadline" => "frist",
        "feedback" => "tilbakemelding"
      }
      
      anglicisms.each do |english, norwegian|
        if text.downcase.include?(english)
          issues << "Replace '#{english}' with '#{norwegian}'"
        end
      end
      
      Result.ok(issues: issues)
    end

    # Persona management
    def self.set_persona(persona)
      return Result.err("Unknown persona: #{persona}") unless SUPPORTED_PERSONAS.include?(persona)
      
      current.write_metadata(:persona, persona)
      Result.ok(persona: persona)
    end

    def self.current_persona
      current.metadata_value(:persona) || :ronin
    end
  end
end
