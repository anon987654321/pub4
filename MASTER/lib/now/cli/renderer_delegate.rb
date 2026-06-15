# frozen_string_literal: true

module Master
  module Now
    class CLI
      # CLI display layer — delegates terminal chrome to Voice::Renderer (O101).
      class RendererDelegate
        def initialize(cli:, voice_renderer:)
          @cli = cli
          @voice = voice_renderer
          @last_status_key = nil
        end

        def render(*args, **kwargs) = @voice.render(*args, **kwargs)
        def speaker_tag = @voice.speaker_tag
        def splash(*) = @voice.splash(*)
        def session_line(*) = @voice.session_line(*)
        def uptime = @voice.uptime
        def closing = @voice.closing

        def prompt_for_mode
          if @cli.focus_mode
            print @voice.render("master$ ", mode: :dim)
            return
          end
          status = status_if_changed
          puts status if status
          sugg = @cli.suggested_next_prompt
          puts @voice.render("  ↳ #{sugg}", mode: :dim) if sugg
          tokens = @cli.session.token_est
          prompt_lines = @voice.prompt_line(
            @cli.agent.model, @cli.session.phase,
            last_ok: @cli.last_ok, violations: @cli.violations, tokens: tokens, cost: @cli.session.cost
          )
          puts prompt_lines.first
          print prompt_lines.last
        end

        def status_if_changed
          key = [@cli.violations, @cli.agent.model, @cli.session.cost, @cli.session.messages.size]
          return nil if key == @last_status_key
          @last_status_key = key
          @voice.status_row(
            uptime: @voice.uptime, turns: @cli.session.messages.size, violations: @cli.violations
          )
        end

        def display_result(result, accumulated, streamed)
          case result
          in Master::Result::Ok => ok
            @cli.last_ok = true
            display_ok(ok, accumulated, streamed)
          in Master::Result::Err => err
            @cli.last_ok = false
            if err.category == :shutdown
              @cli.exit_cli
            else
              puts
              puts @voice.render(format_error_message(err), mode: :error)
              puts
            end
          end
        end

        def display_ok(_ok, _accumulated, streamed)
          if streamed
            puts
            puts
          else
            print "\r\e[K" if $stdout.isatty
            value = _ok.value
            rendered = value.is_a?(Hash) ? value[:rendered] : nil
            text = rendered || value.to_s
            puts @voice.speaker_tag
            puts text
            puts
          end
          print_cost_tooltip
          print_chips if @cli.show_chips
        end

        def format_error_message(err)
          error_text = err.message.to_s
          return error_text if error_text.bytesize <= 200
          error_text[0, 197] + "…"
        end

        def print_cost_tooltip
          now_cost = @cli.session.cost.to_f
          delta = now_cost - @cli.last_cost
          @cli.last_cost = now_cost
          tokens = @cli.session.token_est
          cents = (delta * 100).round(2)
          return if cents.zero? && tokens.zero?
          label = cents < 0.01 ? "$0.00" : "¢#{format('%.2f', cents)}"
          line = "cost: +#{label} · #{tokens} tok · #{short_model(@cli.agent.model)}"
          puts @voice.render(line, mode: :dim)
        end

        def print_chips
          chips = @cli.next_action_chips
          return if chips.empty?
          puts @voice.render("  next: #{chips.join("  ")}", mode: :dim)
        end

        private

        def short_model(model)
          model.to_s.sub(/\Aclaude-cli:/, "").sub(/\Aweb-chat:/, "").split("/").last.to_s.sub(/:free$/, "")
        end
      end
    end
  end
end