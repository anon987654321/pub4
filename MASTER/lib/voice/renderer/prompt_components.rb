# frozen_string_literal: true

module Master
  module Voice
    class Renderer
      # Splash and prompt rendering — separate from Renderer's own
      # render/output-guard responsibility.
      module PromptComponents
        TOKEN_KILO_THRESHOLD = 1000
        PHASE_COLORS = {
          "discover" => :yellow,
          "implement" => :cyan,
          "audit" => :red,
          "grind" => :magenta,
          "polish" => :magenta,
          "watch" => :blue,
        }.freeze

        def splash(model)
          context = splash_context(model)
          lines = splash_dmesg_lines
          lines.concat(runtime_splash_lines(context))
          host_status = Master::Ground::HostBudget.status_line
          lines << d(host_status) if host_status
          lines.concat(["", splash_ready_line(context), ""])
          lines.join("\n")
        end

        alias banner splash

        def prompt_line(model, phase, **options)
          git = git_prompt_segments
          tokens = options[:tokens]
          cost = cost_label(options[:cost])
          token_segment = if Aesthetic.wscons?
                            d("tokens0: #{token_label(tokens)}")
                          else
                            "↖ #{token_bar(tokens)}#{token_label(tokens)}"
                          end
          line = [git, @p.dim(short_model(model)), token_segment,
                  context_label(tokens), cost, violation_badge(options.fetch(:violations, 0)),
                  phase_label(phase)].reject(&:empty?).join("  ")
          prompt = phase_prompt(options.fetch(:last_ok, true), phase)
          [line, prompt + " "]
        end

        def phase_tinted(text, phase)
          return @p.dim(text) if Aesthetic.wscons?

          color = PHASE_COLORS[phase.to_s]
          color ? @p.dim.public_send(color, text) : @p.dim(text)
        end

        def violation_badge(count)
          count = count.to_i
          if Aesthetic.wscons?
            return d(" [0v]") if count.zero?
            return d(" [#{count}v]") if count < 10

            return @p.red(" [#{count}v]")
          end

          return @p.green(" [0v]") if count.zero?
          return @p.yellow(" [#{count}v]") if count < 10

          @p.bold.red(" [#{count}v]")
        end

        def prompt_token
          Aesthetic.wscons? ? "#{safe_hostname.split('.').first}$" : "master$"
        end

        def phase_prompt(last_ok, phase)
          return @p.red(prompt_token) unless last_ok
          return d(prompt_token) if Aesthetic.wscons?

          color = PHASE_COLORS.fetch(phase.to_s, :red)
          @p.bold.public_send(color, prompt_token)
        end

        def cost_label(cost)
          cents = (cost.to_f * 100).round(2)
          return "" if cents.zero?

          label = "¢#{format('%.2f', cents)}"
          if Aesthetic.wscons?
            return d("cost0: #{label}")
          end

          budget = @config.respond_to?(:budget_max) ? @config.budget_max.to_f : 0.0
          return @p.dim(label) unless budget.positive?

          @p.dim("#{label} #{progress_bar(cost.to_f / budget, 4)}")
        end

        def speaker_tag(name = "master")
          return d("#{name}0 at session0:") if Aesthetic.wscons?

          "#{@p.dim('<')}#{@p.bold.red(name)}#{@p.dim('>')}"
        end

        def status_row(uptime:, turns:, violations: 0)
          bits = ["stat0:", uptime, "#{turns} turns"]
          bits << "#{violations}v" if violations.positive?
          @p.dim(bits.join(" "))
        end

        def token_bar(tokens)
          return "" unless tokens&.positive?

          budget = (@config["token_budget"] || Renderer::TOKEN_BUDGET).to_i
          @p.dim(progress_bar(tokens.to_f / budget, Renderer::BAR_CELLS)) + " "
        end

        def token_label(tokens)
          return "0" unless tokens&.positive?

          value = tokens.to_i
          value >= TOKEN_KILO_THRESHOLD ? format("%.1fk", value / 1000.0) : value.to_s
        end

        def context_label(tokens)
          current = token_label(tokens)
          maximum = token_label(Master.context_window(@config["model"]))
          @p.dim("ctx: #{current}/#{maximum}")
        end

        private

        def splash_ready_line(context)
          short_host = context[:host].split(".").first
          if Aesthetic.wscons?
            return d("#{context[:user]}@#{short_host}#{context[:prompt]} ready")
          end

          @p.bold.red("master") + @p.dim("@#{context[:host]} ready")
        end

        def splash_context(model)
          shell = File.basename(ENV["SHELL"] || "zsh")
          {
            now: Time.now,
            host: safe_hostname,
            user: ENV["USER"] || "dev",
            shell:,
            prompt: shell == "zsh" ? "%" : "$",
            revision: git_rev || "1",
            model:,
            web: splash_web_url,
          }
        end

        def splash_web_url
          url = @config["web_public_url"] || Master::Ground::Config::DEFAULTS.fetch("web_public_url")
          token = @config["web_token"]
          token ? "#{url}/?token=#{token}" : url
        end

        def splash_dmesg_lines
          lines = dmesg_lines
          return [] if lines == ["dmesg unavailable"]

          ["", *lines.map { |line| @p.dim(line) }, ""]
        end

        def runtime_splash_lines(context)
          elapsed = monotonic_milliseconds - @boot_ms
          identity_splash_lines(context) + service_splash_lines(context, elapsed)
        end

        def identity_splash_lines(context)
          [
            d("MASTER (CONSTITUTIONAL) ##{context[:revision]}: #{context[:now].strftime('%a %b %e %H:%M:%S %Z %Y')}"),
            d("    #{context[:user]}@#{context[:host]}:#{@config["root"] || Dir.pwd}"),
            d("runtime0: #{RUBY_PLATFORM} ruby #{RUBY_VERSION} #{context[:shell]} #{context[:user]}#{context[:prompt]}"),
            d("aesthetic0: #{Aesthetic.mode}"),
            d("model0: #{short_model(context[:model])}"), d("rev0: #{context[:revision]}")
          ]
        end

        def service_splash_lines(context, elapsed)
          [
            d("soul0: #{soul_version}"),
            d("imports0: #{imports_loaded.join(' ')}"),
            d("orders0: #{active_orders_count} active"), d("security0: #{pledge_status}"),
            d("web0: #{context[:web]}"), d("modules0: ground trace voice now loop judge reach ok"),
            d("mode0: #{Master::CLI::RuntimeMode.summary(config: @config)}"),
            d("boot0: #{elapsed}ms")
          ]
        end

        def git_prompt_segments
          ahead, behind = git_ahead_behind
          branch = git_branch || "detached"
          if Aesthetic.wscons?
            parts = [branch]
            parts << "(dirty)" if git_dirty?
            parts << "+#{ahead}" if ahead.positive?
            parts << "-#{behind}" if behind.positive?
            return d(parts.join(" "))
          end

          dirty = git_dirty? ? @p.red("●") : @p.dim("○")
          ahead_label = ahead.positive? ? @p.dim(" ↑#{ahead}") : ""
          behind_label = behind.positive? ? @p.yellow(" ↓#{behind}") : ""
          @p.red(branch) + dirty + ahead_label + behind_label
        end

        def phase_label(phase)
          phase && phase.to_s != "idle" ? phase_tinted(" :#{phase}", phase) : ""
        end

        def progress_bar(ratio, cells)
          eighths = (ratio.clamp(0.0, 1.0) * cells * 8).round
          full, remainder = eighths.divmod(8)
          partial = full < cells ? Renderer::BAR_FRACTIONS[remainder] : ""
          padding = [cells - full - (partial.empty? ? 0 : 1), 0].max
          ("\u2588" * full) + partial + ("\u00A0" * padding)
        end

        def monotonic_milliseconds
          (Process.clock_gettime(Process::CLOCK_MONOTONIC) * Renderer::MS_PER_SEC).to_i
        end

        def pledge_status
          RUBY_PLATFORM.include?("openbsd") ? "pledge armed" : "pledge unavailable"
        end

        def safe_hostname
          Socket.gethostname
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "renderer.hostname")
          "openbsd"
        end
      end
    end
  end
end
