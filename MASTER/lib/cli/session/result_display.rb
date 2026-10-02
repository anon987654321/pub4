# frozen_string_literal: true

require_relative "../capability_stamp"

module Master
  module CLI
    class Session
      private

      def display_result(result:, accumulated:, streamed:)
        case result
        in Master::Result::Ok => ok
          @last_ok = true
          @exit_code = 0
          display_ok(ok:, accumulated:, streamed:)
        in Master::Result::Err => err
          # A turn the operator cancelled did what was asked; ^C already
          # echoed, so there is nothing to add.
          return if err.category == :abort

          @last_ok = false
          @exit_code = exit_code_for(err)
          return exit_cli if err.category == :shutdown

          Master::Trace::Dmesg.status("err0", format_error_message(err))
        end
      end

      # The error and nothing else, on one line. The category sets the exit
      # code; a playbook lesson on another subject is noise beside an error.
      def format_error_message(err)
        text = err.message.to_s
        text.length <= ERROR_TEXT_MAX_CHARS ? text : "#{text[0, ERROR_TEXT_MAX_CHARS - 1]}…"
      end

      def display_ok(ok:, accumulated:, streamed:)
        text = streamed ? accumulated : success_text(ok)
        routine = !streamed && routine_success?(text)
        command = diagnostic_command(@last_input)

        if streamed
          puts unless text.end_with?("\n")
        elsif command
          # Pipeline commands already streamed their live dmesg units. Other
          # commands get their human-readable result attached to their command
          # unit. Explicit JSON payloads remain payloads, not terminal prose.
          unless %w[fix review critique].include?(command)
            if structured_payload?(text)
              puts text
            else
              Master::Trace::Dmesg::Report.print(command, text)
            end
          end
        else
          print "\r\e[K" if $stdout.isatty
          puts(text) if routine
          puts @refs.renderer.measure(text.chomp, width: reply_measure) unless routine
        end

        Master::Voice::Playback.speak(spoken_form(text))
        print_fix_activity_footer
        print_previous_question_footer
        print_parallel_errors_footer(ok)
        print_capability_stamp(ok)
      end

      def diagnostic_command(input)
        word = input.to_s.strip.split(/\s+/, 2).first.to_s
        return unless word.start_with?("/") || input.to_s.strip.match?(/\A(?:fix|review|critique)\b/i)

        word.delete_prefix("/").downcase
      end

      def structured_payload?(text)
        stripped = text.to_s.lstrip
        stripped.start_with?("{", "[") && stripped.match?(/[}\]]\s*\z/)
      end

      # A pass report is a log, and reading a log aloud from the top takes
      # longer than the pass did. Its milestones were already spoken as they
      # happened (Session::MILESTONE), so what is left to say is the line that
      # closes it. Anything that is not a report is spoken whole.
      REPORT_FOOTER = /\A[a-z]+\d+: (?:complete|incomplete)\b/

      def spoken_form(text)
        last = text.to_s.lines.map(&:strip).reject(&:empty?).last.to_s
        return text unless text.to_s.lines.size > REPORT_MIN_LINES && last.match?(REPORT_FOOTER)

        last
      end

      REPORT_MIN_LINES = 8

      def reply_measure
        [Master::Voice::Renderer::MEASURE, TTY::Screen.width - 1].min
      rescue StandardError
        Master::Voice::Renderer::MEASURE
      end

      def print_previous_question_footer
        return unless @last_input.to_s.lstrip.start_with?("/fix", "fix ")
        return unless @last_ok

        question = @refs.session.last_user_question(before: @last_input)
        return if question.to_s.empty?

        line = "next0: your previous question — #{question}"
        Master::Trace::Dmesg.status("next0", question)
        Master::Voice::Playback.speak(question)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.previous_question_footer", event_bus: @refs.bus)
      end

      def print_fix_activity_footer
        return unless @last_input.to_s.lstrip.start_with?("/fix", "fix ")

        summary = @activity&.fix_summary
        return if summary.to_s.empty?

        Master::Trace::Dmesg.status("fix0", summary.delete_prefix("fix0: "))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.fix_activity_footer", event_bus: @refs.bus)
      end

      def print_capability_stamp(ok)
        return unless verbose_output?

        model = ok.model
        return if model.to_s.empty?

        Master::Trace::Dmesg.status(
          "model0",
          Master::CLI::CapabilityStamp.render(model:, root: Master::ROOT).to_s.delete_prefix("model0 at master0: "),
        )
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.capability_stamp", event_bus: @refs.bus)
      end

      def print_parallel_errors_footer(ok)
        value = ok.value
        return unless value.respond_to?(:[])

        errors = Array(value[:_parallel_errors]).map(&:to_s).reject(&:empty?)
        timeout = value[:_parallel_timeout]
        stage_err = value[:_stage_error].to_s
        lines = errors
        lines << "parallel timeout" if timeout
        lines << stage_err unless stage_err.empty?
        return if lines.empty?

        Master::Trace::Dmesg.status("parallel0", lines.first(3).join("; "))
      end

      def success_text(ok)
        value = ok.value
        return value.to_s unless value.respond_to?(:[])

        rendered = value[:rendered].to_s
        return rendered unless rendered.empty?

        value[:output].to_s
      end

      def routine_success?(text)
        text = text.to_s
        !text.empty? && text.lines.size == 1 && text.length <= ROUTINE_SUCCESS_MAX_LENGTH
      end

      def violations_count
        @violations_mutex.synchronize { @violations }
      end

      def set_violations(count)
        @violations_mutex.synchronize do
          @violations = count
          @prev_violations = count
        end
      end

      def exit_code_for(err)
        case err.category
        when :validation, :policy, :axiom_violation
          1
        when :provider_error, :llm_failure, :llm_call_failure, :no_api_key
          3
        else
          2
        end
      end
    end
  end
end
