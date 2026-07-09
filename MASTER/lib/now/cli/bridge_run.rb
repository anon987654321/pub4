# frozen_string_literal: true

module Master
  module Now
    class CLI
      private

      def print_bridge_footer(fold, state:)
        lines = []
        summary = fold[:summary].to_s.strip
        lines << summary unless summary.empty?
        lines << "core: #{fold[:reason]} turns=#{fold[:turns]}"
        return if lines.empty?

        puts
        lines.each { |line| puts @refs.renderer.render(line, mode: :dim) }
        puts
      end
    end
  end
end