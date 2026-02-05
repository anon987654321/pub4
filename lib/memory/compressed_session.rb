# frozen_string_literal: true
require "json"
require "fileutils"

module MASTER
  module Memory
    class CompressedSession
      attr_reader :session_id, :events, :compressed_summary, :principle_priorities

      def self.sessions_dir
        @sessions_dir ||= File.join(MASTER.root, "var", "sessions")
      end

      def initialize(session_id = nil, llm: nil)
        @session_id = session_id || generate_session_id
        @llm = llm
        @events = []
        @compressed_summary = nil
        @principle_priorities = Hash.new(0)
        
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

        # Auto-update principle priorities if violation detected
        if event_type == :violation && data[:principle]
          update_principle_priorities(data[:principle])
        end
      end

      # Finalize and compress the session
      def finalize_and_compress
        return nil if @events.empty? || !@llm

        puts "🗜️  Compressing session (#{@events.size} events)..."

        prompt = <<~PROMPT
          Compress this coding session into key learnings (max 250 words).

          Events: #{@events.size} total
          #{format_events_for_compression}

          Extract:
          1. Files/code analyzed and key findings
          2. Patterns of violations and recurring issues
          3. Fixes applied successfully
          4. Key decisions and reasoning
          5. Areas needing attention

          Format as concise bullet points. Focus on actionable insights.
        PROMPT

        result = @llm.chat(prompt, tier: :medium, cache: false)
        @compressed_summary = result.ok? ? result.value : "Compression failed: #{result.error}"
        
        # Save compressed session
        save_compressed
        
        puts "✓ Session compressed and saved"
        @compressed_summary
      end

      # Inject context into next session
      def inject_context
        return "" unless @compressed_summary

        prefix = "[Memory] Previous session context:\n\n"
        priorities = format_principle_priorities
        
        context = prefix + @compressed_summary
        context += "\n\n#{priorities}" unless priorities.empty?
        context
      end

      # Update principle priorities based on violations
      def update_principle_priorities(principle_name)
        @principle_priorities[principle_name] += 1
      end

      # Get prioritized list of principles
      def prioritized_principles
        @principle_priorities.sort_by { |_, count| -count }.to_h
      end

      # Save full session
      def save
        return if @disabled
        
        path = File.join(self.class.sessions_dir, "#{@session_id}.json")
        File.write(path, {
          session_id: @session_id,
          events: @events,
          principle_priorities: @principle_priorities,
          created_at: Time.now.iso8601
        }.to_json)
      end

      # Load previous session
      def self.load(session_id)
        path = File.join(sessions_dir, "#{session_id}.json")
        return nil unless File.exist?(path)

        data = JSON.parse(File.read(path))
        session = new(data["session_id"])
        session.instance_variable_set(:@events, data["events"] || [])
        session.instance_variable_set(:@principle_priorities, data["principle_priorities"] || {})
        session
      end

      # Load most recent compressed session
      def self.load_latest_compressed
        return nil unless Dir.exist?(sessions_dir)
        
        files = Dir.glob(File.join(sessions_dir, "*.compressed.json")).sort
        return nil if files.empty?

        data = JSON.parse(File.read(files.last))
        session = new(data["session_id"])
        session.instance_variable_set(:@compressed_summary, data["compressed"])
        session.instance_variable_set(:@principle_priorities, data["principle_priorities"] || {})
        session
      rescue => e
        nil
      end

      # Load latest context for injection
      def self.load_latest_context
        session = load_latest_compressed
        session&.inject_context || ""
      end

      private

      def generate_session_id
        Time.now.strftime("%Y%m%d_%H%M%S")
      end

      def format_events_for_compression
        # Take last 100 events for compression
        recent_events = @events.last(100)
        
        # Group by type
        by_type = recent_events.group_by { |e| e[:type] }
        
        summary = []
        by_type.each do |type, events|
          summary << "#{type.upcase}: #{events.size} events"
          # Show sample events
          events.first(3).each do |e|
            data_str = truncate(e[:data].inspect, 80)
            summary << "  - #{e[:timestamp]}: #{data_str}"
          end
        end
        
        summary.join("\n")
      end

      def format_principle_priorities
        return "" if @principle_priorities.empty?
        
        top_violations = prioritized_principles.first(5)
        return "" if top_violations.empty?
        
        "**Frequently Violated Principles:**\n" +
        top_violations.map { |name, count| "- #{name} (#{count}x)" }.join("\n")
      end

      def truncate(str, len)
        str.length > len ? "#{str[0..len]}..." : str
      end

      def save_compressed
        return if @disabled
        
        path = File.join(self.class.sessions_dir, "#{@session_id}.compressed.json")
        File.write(path, {
          session_id: @session_id,
          compressed: @compressed_summary,
          principle_priorities: @principle_priorities,
          event_count: @events.size,
          compressed_at: Time.now.iso8601
        }.to_json)
      end
    end
  end
end
