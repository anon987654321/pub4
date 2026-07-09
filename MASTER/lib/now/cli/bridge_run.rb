# frozen_string_literal: true

module Master
  module Now
    class CLI
      private

      def run_core_bridge_input(input, state:, accumulated:)
        goal = input.to_s.strip
        return Master::Result.err(Master.no_api_key_message, category: :no_api_key) unless Master.any_api_key_present?

        on_turn = lambda do |line|
          accumulated << line << "\n"
          handle_stream_text(line + "\n", state) if $stdout.isatty
        end

        fold = Master::Now::CoreBridge.run(
          goal,
          root: @refs.root,
          bus: @refs.bus,
          model_id: @refs.agent&.model,
          on_turn:
        )
        print_bridge_footer(fold, state:) if state[:streamed]
        to_bridge_result(fold)
      rescue StandardError => e
        Master::Result.err("core: #{e.message}", category: :infrastructure)
      end

      def to_bridge_result(fold)
        text = bridge_output_text(fold)
        value = { output: text, rendered: text, core: fold }
        return Master::Result.ok(value) if fold[:reason] == :complete

        Master::Result.err(text, category: :policy)
      end

      def bridge_output_text(fold)
        header = "core: #{fold[:reason]} turns=#{fold[:turns]}"
        [header, *fold[:transcript], fold[:summary]].compact.join("\n")
      end

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