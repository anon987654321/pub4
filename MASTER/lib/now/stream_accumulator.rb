# frozen_string_literal: true

module Master
  module Now
    class StreamAccumulator
      def initialize(buffer, &on_text)
        @buffer = buffer
        @on_text = on_text
      end

      def call(chunk)
        text = chunk.respond_to?(:content) ? chunk.content.to_s : chunk.to_s
        return if text.empty?

        @on_text.call(text)
        @buffer << text
      end
    end
  end
end
