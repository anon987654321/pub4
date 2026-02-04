# frozen_string_literal: true
require "json"
require "fileutils"

module Master
  module Memory
    class Session
      def self.sessions_dir
        @sessions_dir ||= File.join(Master::ROOT, "var", "sessions")
      end

      attr_reader :session_id, :events

      def initialize(session_id = nil)
        @session_id = session_id || Time.now.to_i.to_s
        @events = []
        @compressed = nil
        begin
          FileUtils.mkdir_p(self.class.sessions_dir)
        rescue Errno::ENOENT, Errno::EACCES => e
          # Can't create sessions dir (sandbox restriction) - memory disabled
          @disabled = true
        end
      end

      # Record every interaction
      def record(event_type, data)
        return if @disabled
        @events << {
          timestamp: Time.now.iso8601,
          type: event_type.to_s,
          data: data
        }
      end

      # Compress session with LLM
      def compress!
        return if @events.empty?

        prompt = <<~PROMPT
          Compress this coding session into key insights (max 200 words):

          #{format_events}

          Extract:
          1. Files analyzed and key findings
          2. Principles violated and patterns
          3. Fixes applied
          4. Decisions made

          Format as bullet points.
        PROMPT

        llm = Master::LLM.new
        result = llm.ask(prompt, tier: :medium)
        @compressed = result.ok? ? result.value : "Compression failed: #{result.error}"
        save_compressed
        @compressed
      end

      # Inject into next session's context
      def inject_context
        return "" unless @compressed

        <<~CONTEXT
          ## Previous Session Context (#{@session_id})

          #{@compressed}
        CONTEXT
      end

      # Save full session
      def save
        return if @disabled
        path = File.join(self.class.sessions_dir, "#{@session_id}.json")
        File.write(path, {
          session_id: @session_id,
          events: @events,
          created_at: Time.now.iso8601
        }.to_json)
      end

      # Load previous session
      def self.load(session_id)
        path = File.join(sessions_dir, "#{session_id}.json")
        return nil unless File.exist?(path)

        data = JSON.parse(File.read(path))
        session = new(data["session_id"])
        session.instance_variable_set(:@events, data["events"].map { |e| e.transform_keys(&:to_sym) })
        session
      end

      # Load most recent compressed session
      def self.load_latest_context
        return "" unless Dir.exist?(sessions_dir)
        files = Dir.glob(File.join(sessions_dir, "*.compressed.json")).sort.last
        return "" unless files

        data = JSON.parse(File.read(files))
        data["compressed"] || ""
      rescue
        ""
      end

      private

      def format_events
        @events.last(50).map do |e|
          "[#{e[:timestamp]}] #{e[:type]}: #{truncate(e[:data].inspect, 100)}"
        end.join("\n")
      end

      def truncate(str, len)
        str.length > len ? "#{str[0..len]}..." : str
      end

      def save_compressed
        return if @disabled
        path = File.join(self.class.sessions_dir, "#{@session_id}.compressed.json")
        File.write(path, {
          session_id: @session_id,
          compressed: @compressed,
          event_count: @events.size,
          compressed_at: Time.now.iso8601
        }.to_json)
      end
    end
  end
end
