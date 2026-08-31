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
          @last_ok = false
          @exit_code = exit_code_for(err)
          if err.category == :shutdown
            exit_cli
          else
            puts
            error_text = format_error_message(err)
            puts @refs.renderer.render(error_text, mode: :error)
            puts
          end
        end
      end

      CATEGORY_PLAYBOOK = {
        budget: :process,
        provider_error: :master,
        llm_failure: :master,
        validation: :process,
        policy: :process,
        axiom_violation: :master,
      }.freeze

      def format_error_message(err)
        parts = []
        parts << "[#{err.category}]" if err.respond_to?(:category) && err.category
        parts << err.message.to_s
        hint = playbook_hint_for(err)
        parts << hint if hint
        error_text = parts.join(" ")
        return error_text if error_text.bytesize <= ERROR_TEXT_MAX_BYTES

        error_text[0, ERROR_TEXT_MAX_BYTES - 3] + "…"
      end

      def playbook_hint_for(err)
        cat = err.category&.to_sym
        return unless cat
        return if @seen_error_categories[cat]

        @seen_error_categories[cat] = true
        area = CATEGORY_PLAYBOOK[cat]
        lesson = Master::Ground::OperatorPlaybook.for_area(area || :process).first
        return unless lesson

        Master::Ground::OperatorPlaybook.format_lesson(lesson)
      end

      def display_ok(ok:, accumulated:, streamed:)
        if streamed
          puts
          puts
          spoken = accumulated
        else
          print "\r\e[K" if $stdout.isatty
          text = success_text(ok)
          if routine_success?(text)
            puts text
            return
          end
          puts @refs.renderer.speaker_tag
          output_text(text)
          puts
          spoken = text
        end
        # The reply is printed before it is spoken, and speaking does not block
        # the prompt. A routine success returns above and stays silent: "ok" is
        # not worth a synthesis.
        Master::Voice::Playback.speak(spoken)
        print_cost_tooltip
        print_pipeline_timings
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

      def print_pipeline_timings
        timings = @refs.pipeline&.last_timings
        return if timings.nil? || timings.empty?

        total = timings.values.sum
        slow = timings.max_by { |_, ms| ms }
        return unless total.positive?

        line = "pipeline: #{total}ms"
        line += " (slow: #{slow[0]} #{slow[1]}ms)" if slow
        puts @refs.renderer.render(line, mode: :dim)
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

      def output_text(text)
        return puts text unless page_output?(text)

        pager = ENV["PAGER"].to_s.empty? ? "less -R" : ENV["PAGER"]
        IO.popen(pager, "w") { |io| io.write(text) }
      rescue StandardError
        puts text
      end

      def page_output?(text)
        $stdout.isatty && text.to_s.lines.size > TTY::Screen.height
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.page_output?")
        false
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
        line = "cost: +¢#{format('%.2f', cents)} · #{token_delta} tok · #{short_model(@refs.agent.model)}"
        puts @refs.renderer.render(line, mode: :dim)
      end

      def print_changed_files_summary
        out, status = Master::Io::Exec.capture2e("git", "-C", @refs.root, "diff", "--name-only", "HEAD")
        return unless status.success?

        count = out.lines.map(&:strip).reject(&:empty?).size
        puts @refs.renderer.render("#{count} files changed", mode: :dim) if count.positive?
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.changed_files_summary", event_bus: @refs.bus)
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
