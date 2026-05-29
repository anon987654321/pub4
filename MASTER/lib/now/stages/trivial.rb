# frozen_string_literal: true

require_relative "memory"

module Master
  module Now
  module Stages
    # Guard — reject messages that contain prompt-injection patterns.
    # Skips scan when message is absent (command-only paths set no :message).
    # NOTE: This file is a historical consolidation (poor name "trivial.rb").
    class Guard
      def initialize(governor:, injection_guard:)
        @governor = governor
        @injection_guard = injection_guard
      end

      def call(ctx)
        message_text = ctx.message.to_s
        return Result.ok(ctx) if message_text.empty?

        scan = @injection_guard.scan(message_text)
        return Result.err("guard: #{scan.message}", category: :validation) if scan.err?

        Result.ok(ctx)
      end
    end

    # Render — format the final output for display.
    # NOTE: This file is a historical consolidation (poor name "trivial.rb").
    class Render
      def initialize(renderer:)
        @renderer = renderer
      end

      def call(ctx)
        output = ctx.output
        rendered = case output
                   when Result::Ok  then @renderer.render(output.value!, mode: :plain)
                   when Result::Err then @renderer.render(output.message, mode: :error)
                   else                  @renderer.render(output.to_s, mode: :plain)
                   end

        Result.ok(ctx.merge(rendered:))
      end
    end

    # Compatibility name. Use Memory for new code.
    Memo = Memory unless const_defined?(:Memo, false)

    # Intake — parse raw user message into intent + structured fields.
    # Slash syntax: /command args → intent :command.
    # Plain text → intent :llm.
    class Intake
      # m[1] = command name, m[2] = args string (may be empty)
      COMMAND_RE = /\A\s*\/([\w-]+)\s*(.*)/m.freeze

      def call(ctx)
        Master::Now::PipelineContext.validate!(ctx)
        raw = ctx.user_message
        message_text = raw.to_s.strip
        return Result.err("intake: empty message", category: :validation) if message_text.empty?

        if (m = message_text.match(COMMAND_RE))
          command = m[1].downcase
          args    = m[2].strip
          args = nil if args.empty?
          Result.ok(ctx.merge(intent: :command, command: command, args: args))
        else
          Result.ok(ctx.merge(intent: :llm, message: message_text))
        end
      end
    end

    # Execute — call the handler resolved by Route and store its output.
    class Execute
      def call(ctx)
        handler = ctx.handler
        return Result.err("execute: no handler", category: :validation) unless handler

        raw = handler.call(ctx)
        return raw if raw.is_a?(Master::Result::Err)

        output = raw.is_a?(Master::Result) ? raw.value!.to_s : raw.to_s
        Result.ok(ctx.merge(output: output))
      rescue StandardError => e
        Result.err("execute: #{e.message}", category: :unknown)
      end
    end

    # Prune — strip sycophancy and markdown formatting from LLM responses.
    # Rules loaded from data/rules.yml (voice.strunk). Fence-aware: prunes prose, leaves code blocks.
    class Prune
      FENCE_RE = /(```.*?```)/m.freeze

      HEADER_RE = %r{^\#{1,6}\s+}.freeze
      BOLD_RE = /\*\*(.+?)\*\*/
      ITALIC_RE = /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/
      BULLET_RE = /^\s*[-*+]\s+/
      NUMBERED_RE = /^\s*\d+\.\s+/
      HR_RE = /^-{3,}\s*$/
      LINK_RE = /\[([^\]]+)\]\([^)]+\)/
      SYCOPHANCY_RE = /\A\s*(?:
        certainly|of[ ]course|great[ ]question|absolutely|sure|
        happy[ ]to[ ]help|i(?:'d|[ ]would)[ ]be[ ](?:happy|glad)|no[ ]problem
      )[!.,]*\s*/ix

      def call(ctx)
        raw = ctx.output
        output = if raw.is_a?(Master::Result) && raw.ok?
                   raw.value!.to_s
                 elsif raw.is_a?(String)
                   raw
                 else
                   return Result.ok(ctx)
                 end
        return Result.ok(ctx) if output.empty?

        cleaned = prune_mixed(output)
        final = raw.is_a?(Master::Result) ? Result.ok(cleaned.strip) : cleaned.strip
        Result.ok(ctx.merge(output: final))
      end

      private

      def prune_mixed(text)
        segments = text.split(FENCE_RE)
        segments.map { |seg|
          seg.start_with?("```") ? seg : strip_all(seg)
        }.join
      end

      def strip_all(text)
        cleaned = text
        cleaned = cleaned.sub(SYCOPHANCY_RE, "")

        rules.fetch("preambles", []).each { |p| cleaned = cleaned.sub(/\A\s*#{Regexp.escape(p)}\s*/i, "") }
        rules.fetch("endings",   []).each { |e| cleaned = cleaned.sub(/\s*#{Regexp.escape(e)}\s*\z/i, "") }
        rules.fetch("hedges",    []).each do |h|
          if h.is_a?(Hash)
            cleaned = cleaned.gsub(h["pattern"].to_s, h["replace"].to_s)
          else
            cleaned = cleaned.gsub(/\b#{Regexp.escape(h)}\b\s*/i, "")
          end
        end

        cleaned = cleaned.gsub(HEADER_RE, "")
        cleaned = cleaned.gsub(BOLD_RE, '\1')
        cleaned = cleaned.gsub(ITALIC_RE, '\1')
        cleaned = cleaned.gsub(LINK_RE, '\1')
        cleaned = cleaned.gsub(HR_RE, "")
        cleaned = cleaned.gsub(BULLET_RE, "")
        cleaned = cleaned.gsub(NUMBERED_RE, "")
        cleaned = cleaned.gsub(/\n{3,}/, "\n\n")
        cleaned
      end

      def rules
        @rules ||= begin
          data = File.exist?(Master::RULES_PATH) ? Master.load_yaml(Master::RULES_PATH) : {}
          data.dig("voice", "strunk") || {}
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Prune.rules")
        @rules = {}
      end
    end

  end
  end
end
