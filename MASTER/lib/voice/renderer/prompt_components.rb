# frozen_string_literal: true

module Master
  module Voice
    class Renderer
      # Splash and prompt rendering — separate from Renderer's own
      # render/output-guard responsibility.
      #
      # The splash is a dmesg: a version line, the builder line, memory, then
      # one attach line per device, and "root on" last. The prompt is a zsh
      # prompt: where you are, what branch, and the percent sign. Both are plain
      # ASCII, so a serial console and a pipe read the same as a terminal.
      module PromptComponents
        TOKEN_KILO_THRESHOLD = 1000
        PROMPT_PATH_MAX = 44
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
          lines = ["", *identity_lines(context), *splash_dmesg_lines, *device_lines_for(context),
                   root_on_line(context)]
          host_status = Master::Ground::HostBudget.status_line
          lines << d(host_status) if host_status
          lines.concat(["", splash_ready_line(context), ""])
          lines.join("\n")
        end

        alias banner splash

        # [state line or nil, prompt]. The state line carries what a status bar
        # used to: the caller prints it only when one of its values moves.
        def prompt_line(model, phase, **options)
          [state_line(model, **options), zsh_prompt(phase, options.fetch(:last_ok, true))]
        end

        def state_line(model, **options)
          bits = ["model #{short_model(model)}", "ctx #{context_label(options[:tokens])}"]
          violations = options.fetch(:violations, 0).to_i
          bits << "#{violations} #{violations == 1 ? 'violation' : 'violations'}" if violations.positive?
          cost = cost_label(options[:cost])
          bits << cost unless cost.empty?
          d(bits.join(", "))
        end

        def phase_tinted(text, phase)
          return @p.dim(text) if Aesthetic.wscons?

          color = PHASE_COLORS[phase.to_s]
          color ? @p.dim.public_send(color, text) : @p.dim(text)
        end

        def prompt_token
          File.basename(ENV["SHELL"].to_s) == "zsh" ? "%" : "$"
        end

        def phase_prompt(last_ok, phase)
          return @p.red(prompt_token) unless last_ok
          return d(prompt_token) if Aesthetic.wscons?

          color = PHASE_COLORS.fetch(phase.to_s, :red)
          @p.bold.public_send(color, prompt_token)
        end

        def cost_label(cost)
          amount = cost.to_f
          return "" if amount.round(4).zero?

          "cost $#{format('%.4f', amount)}"
        end

        def speaker_tag(name = "master")
          return d("#{name}0 at session0:") if Aesthetic.wscons?

          "#{@p.dim('<')}#{@p.bold.red(name)}#{@p.dim('>')}"
        end

        def token_label(tokens)
          return "0" unless tokens&.positive?

          value = tokens.to_i
          value >= TOKEN_KILO_THRESHOLD ? format("%.1fk", value / 1000.0) : value.to_s
        end

        def context_label(tokens)
          "#{token_label(tokens)}/#{token_label(Master.context_window(@config['model']))}"
        end

        private

        def zsh_prompt(phase, last_ok)
          [d(prompt_path), git_prompt_segments, phase_label(phase),
           phase_prompt(last_ok, phase)].reject(&:empty?).join(" ") + " "
        end

        # zsh's own %~: home as a tilde, and a long path cut from the left so
        # the tail you are actually in stays readable.
        def prompt_path
          path = Dir.pwd.sub(/\A#{Regexp.escape(Dir.home)}/, "~")
          return path if path.length <= PROMPT_PATH_MAX

          ".../#{path.split('/').last(2).join('/')}"
        end

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
            prompt: prompt_token,
            revision: git_rev || "1",
            build: build_number,
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

          lines.map { |line| d(line) }
        end

        # OpenBSD 7.1 (GENERIC.MP) #400: date / builder@host:/path
        def identity_lines(context)
          [
            d("MASTER #{soul_version} (CONSTITUTIONAL) ##{context[:build]}: " \
              "#{context[:now].strftime('%a %b %e %H:%M:%S %Z %Y')}"),
            d("    #{context[:user]}@#{context[:host]}:#{@config['root'] || Dir.pwd}"),
          ]
        end

        def device_lines_for(context)
          mode = Master::CLI::RuntimeMode.summary(config: @config).split(", ")
          [
            d("ruby0 at mainbus0: ruby #{RUBY_VERSION} #{RUBY_PLATFORM}"),
            d("shell0 at mainbus0: #{context[:shell]}, user #{context[:user]}"),
            d("soul0 at mainbus0: constitution rev #{soul_version}"),
            d("soul0: imports #{imports_loaded.join(' ')}"),
            d("soul0: #{active_orders_count} orders active"),
            *model_device_lines(context),
            d("mode0 at mainbus0: #{mode.first(3).join(', ')}"),
            d("mode0: #{mode.drop(3).join(', ')}"),
            d("aesthetic0 at mode0: #{Aesthetic.mode}"),
            d("module0 at mainbus0: #{module_names.join(' ')}"),
            d("web0 at mainbus0: #{context[:web]}"),
            d("pledge0 at mainbus0: #{pledge_status}"),
          ]
        end

        def model_device_lines(context)
          [
            d("model0 at mainbus0: #{short_model(context[:model])}"),
            d("model0: #{provider_for(context[:model])}, " \
              "#{token_label(Master.context_window(@config['model']))} context"),
          ]
        end

        # dmesg ends where the system starts: the root device, then how long it
        # took to get there.
        def root_on_line(context)
          d("root on master0 (#{context[:revision]}) boot #{monotonic_milliseconds - @boot_ms}ms")
        end

        def git_prompt_segments
          ahead, behind = git_ahead_behind
          branch = git_branch || "detached"
          parts = [git_dirty? ? "#{branch}*" : branch]
          parts << "+#{ahead}" if ahead.positive?
          parts << "-#{behind}" if behind.positive?
          label = parts.join(" ")
          Aesthetic.wscons? ? d(label) : @p.red(label)
        end

        def phase_label(phase)
          phase && phase.to_s != "idle" ? phase_tinted("(#{phase})", phase) : ""
        end

        def monotonic_milliseconds
          (Process.clock_gettime(Process::CLOCK_MONOTONIC) * Renderer::MS_PER_SEC).to_i
        end

        def build_number
          stdout, _stderr, status = Master::Io::Exec.capture3("git", "rev-list", "--count", "HEAD")
          status.success? && !stdout.strip.empty? ? stdout.strip : "1"
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "renderer.build_number")
          "1"
        end

        def pledge_status
          RUBY_PLATFORM.include?("openbsd") ? "armed" : "unavailable"
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
