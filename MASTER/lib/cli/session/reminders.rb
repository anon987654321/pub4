# frozen_string_literal: true

require_relative "../../ground/assistant_tasks"

module Master
  module CLI
    class Session
      # Rings a task whose due time has passed, once: a remind0 line above the
      # prompt, the same words spoken, and a reminder:due event for the face. Only
      # an open interactive session rings; AssistantTasks::DELIVERY says so when a
      # due time is accepted.
      REMINDER_POLL_S = 30

      private

      def start_reminder_watch
        return unless $stdin.tty? && $stdout.tty?
        return if Fiber[:master_visitor] == true

        @reminder_thread = Thread.new do
          loop do
            ring_due_reminders
            sleep REMINDER_POLL_S
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.reminders", event_bus: @refs.bus)
        end
      end

      def stop_reminder_watch
        @reminder_thread&.kill
        @reminder_thread = nil
      end

      def ring_due_reminders(tasks: Master::Ground::AssistantTasks.new(root: @refs.root, bus: @refs.bus))
        tasks.due_reminders.each do |task|
          tasks.call(action: "reminded", id: task.fetch("id"))
          terminal_puts("remind0: #{task.fetch('title')}")
          redraw_active_input
          @refs.bus&.publish("reminder:due", task_id: task.fetch("id"))
          Master::Voice::Playback.speak("Reminder: #{task.fetch('title')}")
        end
      end
    end
  end
end
