# frozen_string_literal: true

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

          puts @refs.renderer.render(format_error_message(err), mode: :error)
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
        if streamed
          puts unless text.end_with?("\n")
        else
          print "\r\e[K" if $stdout.isatty
          return puts(text) if routine_success?(text)

          # Printed, never paged: a pager takes the terminal from Reline while
          # other threads still write to it, and a ^C there lands in the shell.
          # Scrollback is the pager. No speaker tag either: the reply sits under
          # the line that asked for it, at full weight among dim system lines.
          puts @refs.renderer.measure(text.chomp, width: reply_measure)
        end
        # The reply is printed before it is spoken, and speaking does not block
        # the prompt. A routine success returns above and stays silent: "ok" is
        # not worth a synthesis.
        Master::Voice::Playback.speak(text)
        print_reply_footers(ok)
        puts
      end

      def reply_measure
        [Master::Voice::Renderer::MEASURE, TTY::Screen.width - 1].min
      rescue StandardError
        Master::Voice::Renderer::MEASURE
      end

      def print_reply_footers(ok)
        print_cost_tooltip
        print_parallel_errors_footer(ok)
        print_changed_files_summary
        print_chips if @show_chips
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

        puts @refs.renderer.render("parallel: #{lines.first(3).join(' · ')}", mode: :warning)
      end

      def success_text(ok)
        value = ok.value
        rendered = value.respond_to?(:[]) ? value[:rendered] : nil
        rendered || (value.respond_to?(:[]) ? value[:output].to_s : value.to_s)
      end

      def routine_success?(text)
        text = text.to_s
        !text.empty? && text.lines.size == 1 && text.length <= ROUTINE_SUCCESS_MAX_LENGTH
      end

      def print_cost_tooltip
        now_cost = @refs.session.cost.to_f
        now_tokens = @refs.session.tokens_billed.to_i
        delta = now_cost - @last_cost
        token_delta = now_tokens - @last_tokens.to_i
        @last_cost = now_cost
        @last_tokens = now_tokens
        cents = (delta * 100).round(2)
        return if cents.zero? && token_delta.zero?
        line = "cost: +¢#{format('%.2f', cents)}, #{token_delta} tokens, #{short_model(@refs.agent.model)}"
        puts @refs.renderer.render(line, mode: :dim)
      end

      # The files this turn wrote, from WriteTracker, which run_input resets.
      # `git diff HEAD` counts every dirty file in a shared checkout, other
      # sessions' work included, whatever this turn did.
      def print_changed_files_summary
        count = Master::Trace::WriteTracker.current&.paths.to_a.size
        return unless count.positive?

        puts @refs.renderer.render("#{count} #{count == 1 ? 'file' : 'files'} written", mode: :dim)
      end

      def print_chips
        chips = next_action_chips
        return if chips.empty?
        puts @refs.renderer.render("  next: #{chips.join(" ")}", mode: :dim)
      end

      # Only commands the registry answers. This offered [/fix], [/why] and [/last]
      # unconditionally and three of the four were unknown commands, so the line
      # whose whole job is to name the next open door named three closed ones.
      # Filtering against the live list keeps it honest as commands move.
      def next_action_chips
        offered = %w[fix undo why last].select { |name| SLASH_COMMANDS.include?("/#{name}") }
        current = violations_count
        offered.map { |name| name == "fix" ? "[/fix #{current}v]" : "[/#{name}]" }
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

      def short_model(model)
        model.to_s.sub(/\Aclaude-cli:/, "").sub(/\Aweb-chat:/, "").split("/").last.to_s.sub(/:free$/, "")
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
