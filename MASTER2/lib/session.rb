# frozen_string_literal: true

require "securerandom"
require "json"

module MASTER
  # Session - Persistent session management with auto-save
  class Session
    attr_reader :id, :created_at, :history, :metadata

    def initialize(id: nil)
      @id = id || SecureRandom.uuid
      @created_at = Time.now.utc
      @history = []
      @metadata = {}
      @dirty = false
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

    def set_metadata(key, value)
      @metadata[key.to_sym] = value
      @dirty = true
    end

    def get_metadata(key)
      @metadata[key.to_sym]
    end

    def dirty?
      @dirty
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

    def to_h
      {
        id: @id,
        created_at: @created_at.iso8601,
        messages: @history.size,
        cost: total_cost,
        metadata: @metadata,
      }
    end
  end
end
