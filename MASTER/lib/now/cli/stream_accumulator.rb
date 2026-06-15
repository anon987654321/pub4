# frozen_string_literal: true

module Master
  module Now
    class CLI
      # O306/O409 — replaces chunk_accumulator lambda with a testable object.
      class StreamAccumulator
        def initialize(buffer)
          @buffer = buffer
        end

        def handler(&block)
          lambda do |chunk|
            text = chunk.respond_to?(:content) ? chunk.content.to_s : chunk.to_s
            next if text.empty?

            block.call(text) if block
            @buffer << text
          end
        end
      end
    end
  end
end