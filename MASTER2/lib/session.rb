# frozen_string_literal: true

require "securerandom"
require "json"
require "time"
require "fileutils"

module MASTER
  # Memory - Session cache and persistence
  # STORAGE ARCHITECTURE:
  # - Session state is stored as JSON files in .sessions/ directory
  # - Each session has a unique ID and is saved via save_session() method
  # - DB JSONL system (db_jsonl.rb) is separate and used for learning feedback only
  # - Do not mix Memory (sessions) with DB (learnings/feedback)
  module Memory
    COMPRESS_AFTER_MESSAGES = 10
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
      }.freeze,
      {
        question: "What patterns kept recurring?",
        action: "Codify as detection rules",
        category: :pattern
      }.freeze,
      {
        question: "What questions yielded good results?",
        action: "Add to hierarchy questions for reuse",
        category: :question
      }.freeze,
      {
        question: "What manual steps could be automated?",
        action: "Add as new command or automation",
        category: :automation
      }.freeze,
      {
        question: "What external tools/APIs were useful?",
        action: "Add to providers/integrations",
        category: :tool
      }.freeze
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

  # SessionReplay - Render conversation timelines with cost annotations and diffs
  # Enables auditing of self-runs and refactoring sessions
  # Merged from session_replay.rb for DRY and cohesion
  module SessionReplay
    extend self

    # Replay a session by ID
    # Returns Result.ok with rendered timeline
    def replay(session_id, format: :terminal)
      data = Memory.load_session(session_id)
      return Result.err("Session not found: #{session_id}") unless data

      history = data[:history] || []
      return Result.err("Empty session") if history.empty?

      case format
      when :terminal
        render_terminal(data, history)
      when :json
        render_json(data, history)
      when :markdown
        render_markdown(data, history)
      else
        Result.err("Unknown format: #{format}")
      end
    end

    # List sessions with summary info
    def list_with_summaries(limit: 20)
      sessions = Memory.list_sessions
      return Result.ok([]) if sessions.empty?

      summaries = sessions.last(limit).map do |id|
        data = Memory.load_session(id)
        next unless data

        history = data[:history] || []
        {
          id: id,
          short_id: UI.truncate_id(id),
          messages: history.size,
          cost: history.sum { |h| h[:cost] || 0 },
          created_at: data[:created_at],
          duration: calculate_duration(history),
          has_diffs: history.any? { |h| h.dig(:metadata, :contains_diff) || h[:type] == :diff },
          crashed: data.dig(:metadata, :crashed) || false,
          metadata: data[:metadata] || {}
        }
      end.compact

      Result.ok(summaries)
    end

    # Diff two sessions
    def diff_sessions(id_a, id_b)
      data_a = Memory.load_session(id_a)
      data_b = Memory.load_session(id_b)

      return Result.err("Session A not found: #{id_a}") unless data_a
      return Result.err("Session B not found: #{id_b}") unless data_b

      diff = {
        session_a: { id: id_a, messages: (data_a[:history] || []).size },
        session_b: { id: id_b, messages: (data_b[:history] || []).size },
        cost_diff: (data_b[:history] || []).sum { |h| h[:cost] || 0 } -
                   (data_a[:history] || []).sum { |h| h[:cost] || 0 },
      }

      Result.ok(diff)
    end

    private

    def render_terminal(data, history)
      output = []
      output << UI.bold("Session Replay: #{UI.truncate_id(data[:id])}")
      output << UI.dim("Created: #{data[:created_at]}")
      output << UI.dim("Messages: #{history.size}")
      output << ""

      total_cost = 0.0
      history.each_with_index do |msg, idx|
        role = (msg[:role] || "unknown").to_s
        content = msg[:content] || ""
        cost = msg[:cost] || 0
        model = msg[:model]
        timestamp = msg[:timestamp]
        total_cost += cost

        # Role indicator
        role_prefix = case role
                      when "user"
                        UI.cyan("▶ USER")
                      when "assistant"
                        UI.green("◀ ASSISTANT")
                      when "system"
                        UI.yellow("⚙ SYSTEM")
                      else
                        UI.dim("? #{role.upcase}")
                      end

        # Turn header
        turn_info = ["##{idx + 1}", role_prefix]
        turn_info << UI.dim("[#{model.split('/').last}]") if model
        turn_info << UI.dim(UI.currency_precise(cost)) if cost > 0
        turn_info << UI.dim(timestamp.to_s[11, 8]) if timestamp

        output << turn_info.join(" ")

        # Content (truncated for terminal display)
        preview = content.length > 500 ? content[0, 500] + "\n  #{UI.dim('... (truncated)')}" : content
        preview.each_line do |line|
          output << "  #{line.rstrip}"
        end

        output << ""
      end

      # Summary footer
      output << UI.bold("─" * 40)
      output << "  Total cost: #{UI.currency_precise(total_cost)}"
      output << "  Messages: #{history.size}"
      output << "  Duration: #{calculate_duration(history)}"

      puts output.join("\n")
      Result.ok(messages: history.size, cost: total_cost)
    end

    def render_json(data, history)
      Result.ok(data)
    end

    def render_markdown(data, history)
      lines = ["# Session #{UI.truncate_id(data[:id])}", ""]
      lines << "**Created:** #{data[:created_at]}"
      lines << "**Messages:** #{history.size}"
      lines << ""

      history.each_with_index do |msg, idx|
        role = (msg[:role] || "unknown").to_s
        content = msg[:content] || ""
        cost = msg[:cost]

        lines << "## Turn #{idx + 1} (#{role})"
        lines << "#{content}"
        lines << "*Cost: #{UI.currency_precise(cost)}*" if cost && cost > 0
        lines << ""
      end

      Result.ok(lines.join("\n"))
    end

    def calculate_duration(history)
      return "unknown" if history.empty?

      timestamps = history.map { |h| begin; Time.parse(h[:timestamp]); rescue ArgumentError, TypeError; nil; end }.compact
      return "unknown" if timestamps.size < 2

      seconds = (timestamps.last - timestamps.first).to_i
      if seconds > 3600
        "#{seconds / 3600}h #{(seconds % 3600) / 60}m"
      elsif seconds > 60
        "#{seconds / 60}m #{seconds % 60}s"
      else
        "#{seconds}s"
      end
    end
  end
end
