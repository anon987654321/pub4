# frozen_string_literal: true

require "json"
require_relative "../../ground/swallow"

module Master
  module Review
    class LLMDispatcher
      # Reads `claude --print --output-format stream-json --include-partial-messages` as it arrives and
      # hands each piece of reply text on, so the operator sees the first words while the model is still
      # writing: a whole reply took 10s to arrive in the 2026-10-23 trial, the first words about 3s.

      # The ReAct loop asks this lane for either a <tool_call> block or a final answer, and a tool call must
      # never reach the screen. So text is held back from the first "<" for as long as it could still be the
      # start of "<tool_call", and once a tool call begins nothing more is passed on.
      class ClaudeStream
        TAG = "<tool_call"

        def initialize(&on_text)
          @on_text = on_text
          @line = +""
          @held = +""
          @stopped = false
        end

        # One chunk of the CLI's stdout, which may hold several events or part of one.
        def feed(chunk)
          @line << chunk.to_s.dup.force_encoding(Encoding::UTF_8)
          while (newline = @line.index("\n"))
            event(@line.slice!(0..newline))
          end
        end

        # Whatever text is still held once the reply is complete and held no tool call.
        def finish
          emit_and_clear(@held.slice!(0..)) unless @stopped
        end

        private

        def event(line)
          data = JSON.parse(line)
          delta = data.dig("event", "delta") if data["type"] == "stream_event"
          text(delta["text"].to_s) if delta.is_a?(Hash) && delta["type"] == "text_delta"
        rescue JSON::ParserError => e
          Master::Ground::Swallow.log(e, context: "ClaudeStream.event")
        end

        # Everything before a "<" goes out at once; from the "<" on, text waits until it either begins a tool
        # call (and stops the stream) or cannot (and goes out).
        def text(piece)
          return if @stopped

          @held << piece
          start = @held.index("<")
          emit_and_clear(start ? @held.slice!(0...start) : @held.slice!(0..))
          if @held.start_with?(TAG)
            @stopped = true
          elsif !@held.empty? && !TAG.start_with?(@held)
            emit_and_clear(@held.slice!(0..))
          end
        end

        def emit_and_clear(text)
          emit(text) unless text.empty?
        end

        def emit(text)
          @on_text.call(text.scrub)
        end
      end
    end
  end
end
