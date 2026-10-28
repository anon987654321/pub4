# frozen_string_literal: true

module Master
  module CLI
    class Session
      private

      def setup_signals
        trap("USR1") { on_usr1 }
        trap("INT")  { on_int }
      end

      # Master::LOADER is the loader that owns lib/; reloading is on only under
      # MASTER_DEV=1, and Zeitwerk raises on reload otherwise.
      def on_usr1
        unless Master::LOADER.reloading_enabled?
          Master::Trace::Dmesg.status("reload0", "skipped, reloading is off without MASTER_DEV=1")
          return
        end

        Master::LOADER.reload
        Master::Trace::Dmesg.status("reload0", "complete")
      rescue StandardError => e
        Master::Trace::Dmesg.status("reload0", "failed, #{e.class}: #{e.message}")
      end

      # ^C cancels a running turn; at the prompt it ends the session. A trap
      # interrupts the main thread wherever it stands, where taking a mutex
      # raises ThreadError, so the cancel runs on a thread of its own and the
      # prompt raises Interrupt for repl_loop to close in ordinary context.
      def on_int
        turn = @pipeline_thread
        if turn&.alive?
          # In the interactive queue, Ctrl+C has the same safe semantics as
          # /stop: pause queued turns too. Do mutex work outside the signal trap.
          return Thread.new { stop_interactive_queue } if @turn_worker&.alive?
          return Thread.new do
            @turn_queue_mutex.synchronize { @turn_cancel_requested = true }
            request_or_interrupt_turn(turn, @turn_children, reason: "ctrl_c")
          end
        end

        raise Interrupt
      end

      # Fold-owned work observes cancellation between model, policy and
      # effect boundaries. Do not kill its thread mid-transaction; non-Fold
      # commands retain the established immediate interruption path.
      def request_or_interrupt_turn(turn, children, reason:)
        token = @turn_cancellation
        token&.cancel!(reason: reason.to_s == "ctrl_c" ? "Ctrl-C requested cancellation" : "operator requested cancellation")
        if token&.active?
          answer_pending_terminal_ask("/deny") if terminal_ask_pending?
          @refs.bus&.publish("user:interrupt", reason:, source: "cli", children:)
        else
          cancel_turn(turn, children)
        end
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
