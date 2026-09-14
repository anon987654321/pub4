# frozen_string_literal: true

module Master
  module CLI
    class Session
      private

      def setup_signals
        trap("USR1") { on_usr1 }
        trap("INT")  { on_int }
      end

      def on_usr1
        Zeitwerk::Loader.for_gem.reload
        puts "\n#{@refs.renderer.render("reloaded", mode: :success)}"
      rescue StandardError => e
        puts "\n#{@refs.renderer.render("reload failed: #{e.message}", mode: :error)}"
      end

      # ^C cancels a running turn; at the prompt it ends the session. A trap
      # interrupts the main thread wherever it stands, where taking a mutex
      # raises ThreadError, so this only kills the turn's thread or raises
      # Interrupt, and repl_loop saves on the way out in ordinary context.
      def on_int
        turn = @pipeline_thread
        return turn.kill if turn&.alive?

        raise Interrupt
      end
    end
  end
end
