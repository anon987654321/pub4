# frozen_string_literal: true

module Master
  module CLI
    class Session
      private

      # The summary is the reply, so it sits at full weight under the units
      # and is spoken. The fold's own line comes from the units console when
      # one ran, and from here when none did.
      def print_bridge_footer(fold, state:)
        summary = fold[:summary].to_s.strip
        puts
        unless summary.empty?
          puts @refs.renderer.measure(summary, width: reply_measure)
          Master::Voice::Playback.speak(summary)
        end
        puts @refs.renderer.render("fold0: #{fold[:reason]}, #{fold[:turns]} turns", mode: :dim) unless @unit_sub
      end
    end
  end
end
