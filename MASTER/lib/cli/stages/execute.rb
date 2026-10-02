# frozen_string_literal: true

module Master
  module CLI
    module Stages
      # Execute — call the handler resolved by Route and store its output.
      class Execute
        def initialize(event_bus: nil)
          @bus = event_bus
        end

        def call(ctx)
          handler = ctx.handler
          return Result.err("execute: no handler", category: :validation) unless handler

          raw = handler.call(ctx)
          return raw if raw.is_a?(Result) && raw.err?

          value = raw.is_a?(Result) ? raw.value! : raw
          output = value.to_s
          if output.strip.empty?
            @bus&.publish("command:empty", command: ctx.command)
            return Result.err(
              "command /#{ctx.command} completed without output",
              category: :handler_exception,
            )
          end

          @bus&.publish("command:completed", command: ctx.command, bytes: output.bytesize)
          Result.ok(ctx.merge(output:))
        rescue StandardError => e
          @bus&.publish("command:error", command: ctx.command, error: "#{e.class}: #{e.message}")
          Result.err("execute: #{e.message}", category: :unknown)
        end
      end
    end
  end
end
