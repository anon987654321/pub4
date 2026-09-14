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
      # raises ThreadError, so the cancel runs on a thread of its own and the
      # prompt raises Interrupt for repl_loop to close in ordinary context.
      def on_int
        turn = @pipeline_thread
        return Thread.new { cancel_turn(turn, @turn_children) } if turn&.alive?

        raise Interrupt
      end

      # The thread first, so the turn takes no next step, then its children,
      # which the thread is otherwise left waiting on.
      def cancel_turn(turn, children)
        turn.kill
        @refs.bus&.publish("user:interrupt", reason: "ctrl_c", source: "cli", children:)
      end
    end
  end
end
