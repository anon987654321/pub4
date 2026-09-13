# frozen_string_literal: true

require_relative "../command_registry/formatter"

module Master
  module CLI
    class Session
      private

      def run_undo = report_undo("undo", @refs.undo.undo!)

      def report_undo(verb, res)
        return puts @refs.renderer.render(res.message, mode: :warning) unless res.is_a?(Master::Result) && res.ok?

        puts @refs.renderer.render("#{verb}: #{Array(res.value!).join(", ")}", mode: :success)
      end

      def toggle_focus
        @focus_mode = !@focus_mode
        puts @refs.renderer.render("focus: #{@focus_mode ? "on" : "off"}", mode: :dim)
      end
    end
  end
end
