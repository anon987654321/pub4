# frozen_string_literal: true

require "securerandom"
require "json"
require "time"
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
          next unless data && data[:history]
          
          data[:history].each do |msg|
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

  # SessionCapture - Automatic pattern extraction from successful sessions
  # Ported from MASTER v1 master.yml v49.75 meta_analysis section
  module SessionCapture
    extend self

    QUESTIONS = [
      {
        question: "What new techniques were discovered?",
        action: "Add to structural_analysis or principles",
        category: :technique
      },
      {
        question: "What patterns kept recurring?",
        action: "Codify as detection rules",
        category: :pattern
      },
      {
        question: "What questions yielded good results?",
        action: "Add to hierarchy questions for reuse",
        category: :question
      },
      {
        question: "What manual steps could be automated?",
        action: "Add as new command or automation",
        category: :automation
      },
      {
        question: "What external tools/APIs were useful?",
        action: "Add to providers/integrations",
        category: :tool
      }
    ].freeze

    def capture_file
      File.join(Paths.var, "session_captures.jsonl")
    end

    # Run session capture (call after successful work session)
    def capture(session_id: nil)
      session_id ||= Session.current.id
      
      puts UI.bold("\n📚 Session Capture")
      puts UI.dim("Extracting patterns from this session...\n")

      answers = {}
      
      QUESTIONS.each do |q|
        puts UI.yellow("\n#{q[:question]}")
        puts UI.dim("  Action: #{q[:action]}")
        print "  Answer (or skip): "
        
        answer = $stdin.gets&.chomp&.strip
        next if answer.nil? || answer.empty? || answer.downcase == 'skip'
        
        answers[q[:category]] = answer
      end

      if answers.empty?
        puts UI.dim("\nNo insights captured")
        return Result.ok(captured: false)
      end

      # Save capture
      capture_entry = {
        session_id: session_id,
        timestamp: Time.now.utc.iso8601,
        answers: answers
      }

      File.open(capture_file, "a") do |f|
        f.puts(JSON.generate(capture_entry))
      end

      # Add to learnings automatically
      answers.each do |category, answer|
        learning_category = map_to_learning_category(category)
        if learning_category
          Learnings.record(
            category: learning_category,
            pattern: nil,
            description: answer,
            severity: :info
          )
        end
      end

      puts UI.green("\n✓ Session insights captured and added to learnings")
      
      Result.ok(captured: true, insights: answers.size)
    end

    # Auto-capture if session was successful (called on exit)
    def auto_capture_if_successful
      session = Session.current
      return unless session
      return unless session.metadata_value(:successful)

      puts UI.dim("\n[Auto-capture triggered for successful session]")
      capture(session_id: session.id)
    end

    # Review all captures
    def review
      return Result.err("No captures found") unless File.exist?(capture_file)

      captures = File.readlines(capture_file).map do |line|
        JSON.parse(line, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end.compact

      Result.ok(captures: captures, count: captures.size)
    end

    # Suggest new commands/features based on automation captures
    def suggest_automations
      review_result = review
      return Result.err("No captures to analyze") unless review_result.ok?

      captures = review_result.value[:captures]
      automation_suggestions = captures
        .select { |c| c[:answers][:automation] }
        .map { |c| c[:answers][:automation] }

      Result.ok(suggestions: automation_suggestions)
    end

    private

    def map_to_learning_category(capture_category)
      case capture_category
      when :technique then :good_practice
      when :pattern then :bug_pattern
      when :question then :ux_insight
      when :automation then :architecture
      when :tool then :architecture
      else nil
      end
    end
  end
  # Session - Persistent session management with auto-save
  # STORAGE: Uses Memory module (JSON files in .sessions/)
  # NOTE: DB JSONL system is separate and used by LearningFeedback
  # See learnings.rb line 241-242 for architecture notes
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

    # Class methods for session management
    class << self
      # Load session from storage by ID
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
      rescue StandardError
        # Best effort on crash
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
