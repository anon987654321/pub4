# frozen_string_literal: true

module Master
  module CLI
    class Activity
      def initialize
        reset!
      end

      def reset!
        @pass = nil
        @stage = nil
        @files = nil
        @violations = nil
        @changes = 0
        @council = nil
        @terminal = nil
        @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def record(event, payload = {})
        name = event.to_s
        return if name.empty?

        case name
        when "pipeline:stage_start"
          @stage = payload[:stage].to_s.downcase
        when "fix_loop:pass_start"
          @pass = payload[:pass]
          @files = payload[:file_count]
          @stage = "observe"
        when "fix_loop:scan_progress"
          @stage = "scan"
          @violations = payload[:count] if payload.key?(:count)
        when "fix_loop:ast_fixed", "rule_loop:fix_applied"
          @stage = "repair"
          @changes += 1
        when "council:start", "council:deliberation"
          @stage = "council"
          @council = "reviewing"
        when "council:pass"
          @stage = "council"
          @council = "pass"
        when "council:veto"
          @stage = "council"
          @council = "veto"
        when "fix_loop:clean"
          @stage = "validate"
          @terminal = "clean"
        when "fix_loop:plateau"
          @stage = "plateau"
          @violations = payload[:violations] if payload.key?(:violations)
          @terminal = "plateau"
        when "fix_loop:validation_failed"
          @stage = "validation"
          @terminal = "validation failed"
        when "fix_loop:pass_timeout", "fix_loop:timeout"
          @stage = "timeout"
          @terminal = "timeout"
        end
        self
      rescue StandardError
        self
      end

      def label(stage: nil, elapsed: nil)
        current = @stage.to_s.empty? ? stage.to_s : @stage
        current = "working" if current.empty?

        parts = ["fix0:", current]
        parts << "pass=#{@pass}" if @pass
        parts << "files=#{@files}" if @files
        parts << "violations=#{@violations}" unless @violations.nil?
        parts << "changes=#{@changes}" if @changes.positive?
        parts << "council=#{@council}" if @council && @stage == "council"
        parts << "elapsed=#{elapsed}s" unless elapsed.nil?
        parts.join(" ")
      end

      def fix_summary
        parts = ["fix0:"]
        parts << "pass=#{@pass}" if @pass
        parts << "files=#{@files}" if @files
        parts << "violations=#{@violations}" unless @violations.nil?
        parts << "changes=#{@changes}" if @changes.positive?
        parts << "state=#{@terminal}" if @terminal
        parts.length == 1 ? nil : parts.join(" ")
      end
    end
  end
end
