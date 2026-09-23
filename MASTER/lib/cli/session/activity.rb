# frozen_string_literal: true

module Master
  module CLI
    class Activity
      LIMIT = 9

      def initialize
        reset!
      end

      def reset!
        @counts = Hash.new(0)
        @last = nil
      end

      def record(event, payload = {})
        name = event.to_s
        return if name.empty?

        @last = case name
                when /\A(?:fix|review):/ then name.split(":").last
                when /\A(?:llm|tool):/ then name.split(":").last
                end
        case name
        when /\Afix:change/ then @counts[:changes] += 1
        when /\Afix:pass/ then @counts[:passes] += 1
        when /\A(?:tool:call|tool:start)/ then @counts[:tools] += 1
        when /\A(?:llm:send|llm:call)/ then @counts[:models] += 1
        when /\A(?:council:pass|council:veto)/ then @counts[:council] += 1
        end
        self
      rescue StandardError
        self
      end

      def label(stage:, elapsed:)
        parts = [stage.to_s.empty? ? "working" : stage.to_s]
        parts << "#{@counts[:changes]} changes" if @counts[:changes].positive?
        parts << "#{@counts[:tools]} tools" if @counts[:tools].positive?
        parts << "#{@counts[:models]} model calls" if @counts[:models].positive?
        parts << "#{elapsed}s"
        parts.join(" · ")
      end
    end
  end
end
