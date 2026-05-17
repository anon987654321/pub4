# frozen_string_literal: true

require "json"
require "open3"

module Master
  module Reach
    class Dilla
      TIER = :dangerous
      NAME = "dilla".freeze
      DESCRIPTION = "Capture, separate, study, render, and score audio with the dilla lab.".freeze
      ACTIONS = %w[scan sweep council debug sample source livestream separate render verify chords clean stems study rhythm melody harmony semantics ears].freeze
      INPUT_REQUIRED = %w[source livestream separate clean study rhythm melody harmony semantics ears sample].freeze

      def initialize(root:, governor:, event_bus: nil)
        @root = root
        @governor = governor
        @bus = event_bus
      end

      def call(action:, input: nil, output: nil, kind: nil, live_seconds: nil, bpm: nil, bars: nil)
        action = action.to_s
        return Result.err("dilla: unknown action #{action}", category: :validation) unless ACTIONS.include?(action)
        return Result.err("dilla: input required for #{action}", category: :validation) if INPUT_REQUIRED.include?(action) && input.to_s.empty?

        script = script_path
        return Result.err("dilla: script missing", category: :infrastructure) unless script

        permission = @governor.permit?(NAME, TIER, "dilla #{action} #{input} #{output}")
        return permission if permission.err?

        env = runtime_env(live_seconds:, bpm:, bars:)
        @bus&.publish("tool:before", tool: NAME, action: action, input: input, output: output)
        result = action == "sample" ? sample(script, env, input) : run(script, env, build_argv(action, input:, output:, kind:))
        @bus&.publish("tool:after", tool: NAME, action: action, exit: result.fetch(:exit))
        return Result.ok(result.fetch(:text)) if result.fetch(:exit).zero?

        Result.err("dilla: exit #{result.fetch(:exit)} #{result.fetch(:text)}", category: :provider_error)
      rescue StandardError => error
        Result.err("dilla: #{error.message}", category: :infrastructure)
      end

      private

      def sample(script, env, input)
        source_path = File.join(File.dirname(script), "samples", "source.wav")
        clean_path = File.join(File.dirname(script), "samples", "clean_harmonic.wav")
        first = run(script, env, ["source", input, source_path])
        return first unless first.fetch(:exit).zero?
        second = run(script, env, ["separate", source_path])
        return second unless second.fetch(:exit).zero?
        stem = parse_last_json(second.fetch(:text)).fetch("other")
        run(script, env, ["clean", File.expand_path(stem, File.dirname(script)), clean_path])
      rescue JSON::ParserError, KeyError => error
        { exit: 1, text: "sample: #{error.message}" }
      end

      def run(script, env, argv)
        out, err, status = Open3.capture3(env, "ruby", script, *argv, chdir: File.dirname(script))
        { exit: status.exitstatus || 1, text: format_output(out, err) }
      end

      def build_argv(action, input:, output:, kind:)
        case action
        when "source", "livestream" then [action, input, output].compact
        when "separate", "verify", "rhythm", "melody", "harmony", "semantics", "ears" then [action, input].compact
        when "render" then [action, output].compact
        when "clean" then [action, input, output].compact
        when "stems" then [action, input, output].compact
        when "study" then [action, kind || "rhythm", input].compact
        else [action]
        end
      end

      def parse_last_json(text)
        start = text.rindex("{")
        raise JSON::ParserError, "no json object" unless start
        JSON.parse(text[start..])
      rescue JSON::ParserError
        raise
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
          File.expand_path("../DEPLOY/dilla/dilla.rb", @root),
          File.expand_path("../../DEPLOY/dilla/dilla.rb", @root),
          File.expand_path("../dilla/dilla.rb", @root),
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
