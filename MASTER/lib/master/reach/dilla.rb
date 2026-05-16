# frozen_string_literal: true

require "json"
require "open3"

module Master
  module Reach
    class Dilla
      TIER = :dangerous
      NAME = "dilla".freeze
      DESCRIPTION = "Capture, separate, study, render, and score audio with the dilla lab.".freeze
      ACTIONS = %w[scan sweep council debug sample source livestream separate render verify chords clean stems study rhythm melody ears].freeze

      def initialize(root:, governor:, event_bus: nil)
        @root = root
        @governor = governor
        @bus = event_bus
      end

      def call(action:, input: nil, output: nil, kind: nil, live_seconds: nil, bpm: nil, bars: nil)
        action = action.to_s
        return Result.err("dilla: unknown action #{action}", category: :validation) unless ACTIONS.include?(action)

        script = script_path
        return Result.err("dilla: script missing", category: :infrastructure) unless script

        argv = build_argv(action, input:, output:, kind:)
        permission = @governor.permit?(NAME, TIER, "dilla #{argv.join(' ')}")
        return permission if permission.err?

        env = runtime_env(live_seconds:, bpm:, bars:)
        @bus&.publish("tool:before", tool: NAME, action: action, input: input, output: output)
        out, err, status = Open3.capture3(env, "ruby", script, *argv, chdir: File.dirname(script))
        @bus&.publish("tool:after", tool: NAME, action: action, exit: status.exitstatus)
        return Result.ok(format_output(out, err)) if status.success?

        Result.err("dilla: exit #{status.exitstatus} #{err.strip}", category: :provider_error)
      rescue StandardError => error
        Result.err("dilla: #{error.message}", category: :infrastructure)
      end

      private

      def build_argv(action, input:, output:, kind:)
        case action
        when "source", "livestream" then [action, input, output].compact
        when "separate", "verify", "rhythm", "melody", "ears" then [action, input].compact
        when "render" then [action, output].compact
        when "clean" then [action, input, output].compact
        when "stems" then [action, input, output].compact
        when "study" then [action, kind || "rhythm", input].compact
        else [action]
        end
      end

      def runtime_env(live_seconds:, bpm:, bars:)
        env = {}
        env["LIVE_SECONDS"] = live_seconds.to_i.to_s if live_seconds
        env["BPM"] = bpm.to_f.to_s if bpm
        env["BARS"] = bars.to_i.to_s if bars
        env
      end

      def script_path
        candidates.find { |path| File.exist?(path) }
      end

      def candidates
        [
          File.expand_path("../dilla/dilla.rb", @root),
          File.expand_path("../DEPLOY/dilla/dilla.rb", @root),
          File.expand_path("../../DEPLOY/dilla/dilla.rb", @root),
          File.expand_path("DEPLOY/dilla/dilla.rb", File.dirname(@root))
        ].uniq
      end

      def format_output(out, err)
        lines = (out.to_s + err.to_s).lines.map(&:strip).reject(&:empty?)
        lines.last(120).join("\n")
      end
    end
  end
end
