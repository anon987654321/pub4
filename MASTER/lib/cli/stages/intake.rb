# frozen_string_literal: true

module Master
  module CLI
    module Stages
      # Intake — parse raw user message into intent + structured fields.
      # Slash syntax: /command args -> intent :command.
      # Plain text -> intent :llm.
      class Intake
        # m[1] = command name, m[2] = args string (may be empty)
        COMMAND_RE = /\A\s*\/([\w-]+)\s*(.*)/m.freeze

        def call(ctx)
          Master::CLI::PipelineContext.validate!(ctx)
          Master::Trace::WriteTracker.current&.reset!
          raw = ctx.user_message
          message_text = raw.to_s.strip
          return Result.err("intake: empty message", category: :validation) if message_text.empty?

          expanded_message = expand_file_references(message_text)
          classify_intent(ctx, expanded_message, message_text)
        end

        def classify_intent(ctx, expanded_message, message_text)
          # Unified /run entry point for natural language tasks (better LLM ergonomics)
          if expanded_message.start_with?("/run ")
            desc = expanded_message[5..].strip
            return Result.ok(ctx.merge(intent: :llm, message: desc, original_message: message_text, explicit_run: true))
          end

          if (m = expanded_message.match(COMMAND_RE))
            command = m[1].downcase
            args = m[2].strip
            args = nil if args.empty?
            Result.ok(ctx.merge(intent: :command, command:, args:, original_message: message_text))
          else
            Result.ok(ctx.merge(intent: :llm, message: expanded_message, original_message: message_text))
          end
        end

        private

        def expand_file_references(message)
          refs = message.scan(/@([A-Za-z0-9_\/.\-]+\.[A-Za-z0-9]+)/).flatten.uniq.first(3)
          return message if refs.empty?

          snippets = refs.filter_map do |ref|
            path = File.expand_path(ref, Master::ROOT)
            next unless File.file?(path)

            content = File.read(path, encoding: "UTF-8")
            content = content.bytesize > 12_000 ? content.byteslice(0, 12_000) : content
            "[@#{ref}]\n```text\n#{content}\n```"
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "Intake.expand_file_references")
            nil
          end
          return message if snippets.empty?

          [message, "", snippets.join("\n\n")].join("\n")
        end
      end
    end
  end
end
