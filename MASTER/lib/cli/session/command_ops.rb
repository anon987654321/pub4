# frozen_string_literal: true

module Master
  module CLI
    class Session
      private

      def run_undo = report_undo("undo", @refs.undo.undo!)

      def report_undo(verb, res)
        unless res.is_a?(Master::Result) && res.ok?
          return Master::Trace::Dmesg.status("undo0", "failed, #{res.respond_to?(:message) ? res.message : res}")
        end

        Master::Trace::Dmesg.status("undo0", "#{verb}, #{Array(res.value!).join(", ")}")
      end

      def toggle_focus
        @focus_mode = !@focus_mode
        Master::Trace::Dmesg.status("focus0", @focus_mode ? "on" : "off")
      end
    end
  end
end
