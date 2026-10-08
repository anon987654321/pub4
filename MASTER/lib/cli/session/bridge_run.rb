# frozen_string_literal: true

module Master
  module CLI
    class Session
      private

      # The summary is the reply, so it sits at full weight under the units.
      # The final streamed reply is spoken by result_display; speaking this
      # summary here too queued the same turn a second time.
      # The fold's own line comes from the units console when one ran, and
      # from here when none did.
      def print_bridge_footer(fold, state:)
        summary = fold[:summary].to_s.strip
        puts
        unless summary.empty?
          puts @refs.renderer.measure(summary, width: reply_measure)
        end
        Master::Trace::Dmesg.status("fold0", "#{fold[:reason]}, #{fold[:turns]} turns") unless @unit_sub
      end
    end
  end
end
