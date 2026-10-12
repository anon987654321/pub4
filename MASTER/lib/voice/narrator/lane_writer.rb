# frozen_string_literal: true

module Master
  module Voice
    class Narrator
      # Asks the cheapest live lane of the configured tier for the next beat.
      # Raises Unavailable when no lane can answer; the narrator then speaks
      # from its template and tries again later.
      class LaneWriter
        Unavailable = Class.new(StandardError)

        # `claude --print` inherits these two from a Claude Code session and
        # hangs; unset, it answers in seconds. Text only, no tools: a narrator
        # must not be able to touch the tree.
        SESSION_ENV = { "CLAUDECODE" => nil, "CLAUDE_CODE_ENTRYPOINT" => nil }.freeze
        TEXT_ONLY = ["--tools", "", "--strict-mcp-config"].freeze
        UNSUPPORTED_LANES = %w[grok-cli codex-cli agy web-chat].freeze

        def initialize(config, lanes: Master::Io::LaneSelection, runner: Master::Io::Exec)
          @config = config
          @lanes = lanes
          @runner = runner
        end

        def call(system:, prompt:, max_tokens:)
          model = pick or raise Unavailable, "no live #{@config["lane_tier"]} lane"
          reply = model.start_with?("claude-cli:") ? via_claude_cli(model, system, prompt) : via_ruby_llm(model, system, prompt, max_tokens)
          reply.to_s.strip.then { |text| text.empty? ? raise(Unavailable, "#{model} answered nothing") : text }
        end

        def pick
          tier = @lanes.tier(@config.fetch("lane_tier", "fast"))
          @lanes.order(tier).find { |id| supported?(id) && @lanes.alive?(id) }
        end

        private

        def supported?(id) = UNSUPPORTED_LANES.none? { |lane| id.start_with?(lane) }

        def via_claude_cli(model, system, prompt)
          out, _err, status = @runner.capture3(
            SESSION_ENV, "claude", "--print", "--model", model.split(":", 2).last, *TEXT_ONLY, "--system-prompt", system,
            stdin_data: prompt, timeout: Float(@config.fetch("model_timeout_s", 20))
          )
          raise Unavailable, "claude-cli exited #{status.exitstatus.inspect}" unless status.success?
          raise Unavailable, "claude-cli limit reached" if out.match?(/\A\s*You've hit your/i)

          out
        end

        def via_ruby_llm(model, system, prompt, max_tokens)
          require "ruby_llm"
          chat = RubyLLM.chat(model:).with_instructions(system)
          chat = chat.with_params(max_tokens:) if chat.respond_to?(:with_params)
          chat.ask(prompt).content
        end
      end
    end
  end
end
