# frozen_string_literal: true

module Master
  module Now
    class CLI
      private

      def display_result(result:, accumulated:, streamed:)
        case result
        in Master::Result::Ok => ok
          @last_ok = true
          display_ok(ok:, accumulated:, streamed:)
        in Master::Result::Err => err
          @last_ok = false
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

      def format_error_message(err)
        error_text = err.message.to_s
        return error_text if error_text.bytesize <= 200

        error_text[0, 197] + "…"
      end

      def display_ok(ok:, accumulated:, streamed:)
        if streamed
          puts
          puts
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
        end
        print_cost_tooltip
        print_changed_files_summary
        print_chips if @show_chips
      end

      def success_text(ok)
        value = ok.value
        rendered = value.respond_to?(:[]) ? value[:rendered] : nil
        rendered || (value.respond_to?(:[]) ? value[:output].to_s : value.to_s)
      end

      def routine_success?(text)
        text = text.to_s
        !text.empty? && text.lines.size == 1 && text.length <= 120
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
      rescue StandardError
        false
      end

      def print_cost_tooltip
        now_cost = @refs.session.cost.to_f
        delta = now_cost - @last_cost
        @last_cost = now_cost
        tokens = @refs.session.token_est
        cents  = (delta * 100).round(2)
        return if cents.zero? && tokens.zero?
        line = "cost: +¢#{format('%.2f', cents)} · #{tokens} tok · #{short_model(@refs.agent.model)}"
        puts @refs.renderer.render(line, mode: :dim)
      end

      def print_changed_files_summary
        out, status = Open3.capture2e("git", "-C", @refs.root, "diff", "--name-only", "HEAD")
        return unless status.success?

        count = out.lines.map(&:strip).reject(&:empty?).size
        puts @refs.renderer.render("#{count} files changed", mode: :dim) if count.positive?
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.changed_files_summary", event_bus: @refs.bus)
      end

      def print_chips
        chips = next_action_chips
        return if chips.empty?
        puts @refs.renderer.render("  next: #{chips.join("  ")}", mode: :dim)
      end

      def next_action_chips
        base = ["[/undo]", "[/why]", "[/last]"]
        current = violations_count
        base.unshift("[/fix #{current}v]") if current.positive?
        base
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
    end
  end
end
