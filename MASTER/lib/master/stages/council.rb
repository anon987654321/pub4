# frozen_string_literal: true

require "yaml"

module Master
  module Stages
    # Council — 6-persona deliberation on dangerous or multi-file changes.
    # PRAISE votes are appended to data/exemplars.yml for future reference.
    class Council
      EXEMPLARS_PATH       = File.join(Master::ROOT, "data", "exemplars.yml").freeze
      PATTERNS_PATH        = File.join(Master::ROOT, "data", "council_patterns.yml").freeze
      EXEMPLAR_MSG_CHARS   = 120
      EXEMPLAR_FEEDBACK_CHARS = 240

      def initialize(deliberation:, config: nil, enabled: false, event_bus: nil)
        @deliberation      = deliberation
        @config            = config
        @bus               = event_bus
        @enabled           = @config&.[]("council") == true || enabled
        @dangerous_patterns = load_patterns
      end

      def call(ctx)
        return Result.ok(ctx) unless should_run?(ctx)

        payload = extract_payload(ctx)
        result  = @deliberation.review(payload, context: ctx[:message])
        return result if result.err?

        feedback = result.value!
        log_praise(ctx[:message], feedback) if praise?(feedback)

        Result.ok(ctx.merge(council_feedback: feedback))
      end

      def enable!
        @enabled = true
        @config&.[]=("council", true)
        @config&.save!
      end

      def disable!
        @enabled = false
        @config&.[]=("council", false)
        @config&.save!
      end

      def enabled? = @enabled

      private

      def load_patterns
        data = Master.load_yaml(PATTERNS_PATH)
        (data["dangerous"] || []).flatten.filter_map do |str|
          Regexp.new(str, Regexp::IGNORECASE)
        rescue RegexpError
          nil
        end
      end

      def should_run?(ctx)
        return false if ctx[:intent] == :command
        @enabled || dangerous_request?(ctx) || dangerous_tool?(ctx) || multi_file_diff?(ctx)
      end

      def dangerous_request?(ctx)
        msg = ctx[:message].to_s.gsub(/[[:cntrl:]]/, "")
        !msg.empty? && @dangerous_patterns.any? { |p| msg.match?(p) }
      end

      def dangerous_tool?(ctx)  = ctx[:last_tool_tier] == :dangerous
      def multi_file_diff?(ctx) = extract_payload(ctx).scan(/^(?:---|\+\+\+)\s+[ab]\/(.+)$/).uniq.size >= 2

      def extract_payload(ctx)
        out = ctx[:output]
        case out
        when Result::Ok  then out.value!.to_s
        when Result::Err then ""
        else
          text = out.to_s
          text.empty? ? ctx[:message].to_s : text
        end
      end

      # Detect unanimous or majority PRAISE in council feedback text.
      def praise?(feedback)
        text = feedback.to_s.downcase
        text.scan(/\bpraise\b/).size >= 3
      end

      # Append a PRAISE entry to data/exemplars.yml.
      def log_praise(message, feedback)
        entry = {
          "timestamp" => Time.now.iso8601,
          "message"   => message.to_s[0, EXEMPLAR_MSG_CHARS],
          "feedback"  => feedback.to_s[0, EXEMPLAR_FEEDBACK_CHARS]
        }
        @exemplar_mutex ||= Mutex.new
        @exemplar_mutex.synchronize do
          existing = File.exist?(EXEMPLARS_PATH) ? (Master.load_yaml(EXEMPLARS_PATH) || []) : []
          tmp = "#{EXEMPLARS_PATH}.tmp.#{Process.pid}"
          File.write(tmp, YAML.dump(existing + [entry]))
          File.rename(tmp, EXEMPLARS_PATH)
        end
      rescue StandardError => e
        @bus&.publish("council:exemplar_error", error: e.message)
      end
    end
  end
end
