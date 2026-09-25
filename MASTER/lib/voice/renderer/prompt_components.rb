# frozen_string_literal: true

require "tty-screen"

module Master
  module Voice
    class Renderer
      # Splash and prompt rendering — separate from Renderer's own
      # render/output-guard responsibility.
      #
      # The splash is a dmesg: a version line, the builder line, memory, then
      # one attach line per device, and "root on" last. The prompt is a zsh
      # prompt: where you are, what branch, and the percent sign. Both are plain
      # Splash text is plain ASCII; the interactive prompt may use one Unicode
      # ellipsis where a long path needs it, while the wscons path stays ASCII.
      module PromptComponents
        TOKEN_KILO_THRESHOLD = 1000
        PROMPT_PATH_MAX = 44
        # The prompt token alone carries the phase; the path and state stay quiet.
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
          lines = [*identity_lines(context), *splash_dmesg_lines, *device_lines_for(context),
                   root_on_line(context)]
          host_status = Master::Ground::HostBudget.status_line
          lines << d(host_status) if host_status
          lines.concat(["", splash_ready_line(context)])
          lines.join("\n")
        end

        alias banner splash

        # [state line or nil, prompt]. The state line carries what a status bar
        # used to: the caller prints it only when one of its values moves.
        def prompt_line(model, phase, **options)
          [state_line(model, **options), zsh_prompt(phase, options.fetch(:last_ok, true))]
        end

        def state_line(model, **options)
          bits = ["model0: #{short_model(model)}", "ctx0: #{context_label(options[:tokens], model)}"]
          violations = options.fetch(:violations, 0).to_i
          bits << "scan0: #{violations} violations" if violations.positive?
          d(bits.join(", "))
        end

        def phase_tinted(text, _phase)
          d(text)
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

        def token_label(tokens)
          return "0" unless tokens&.positive?

          value = tokens.to_i
          value >= TOKEN_KILO_THRESHOLD ? format("%.1fk", value / 1000.0) : value.to_s
        end

        def context_label(tokens, model = @config["model"])
          "#{token_label(tokens)}/#{token_label(Master.context_window(model))}"
        end

        private

        # The prompt is set like text, not a status bar: location first,
        # repository state second, phase third, cursor last. Keep the whole line
        # near a 66-character measure when the terminal permits it, and let the
        # path yield before the meaningful state does.
        def zsh_prompt(phase, last_ok)
          git = git_prompt_segments
          phase_text = phase_label(phase)
          suffix = [git, phase_text, phase_prompt(last_ok, phase)].reject(&:empty?).join(" ")
          path = prompt_path(suffix_length: visible_length(suffix))
          [d(path), suffix].reject(&:empty?).join(" ") + " "
        end

        # zsh's own %~: home as a tilde, and a long path cut from the left so
        # the tail you are actually in stays readable. Use a typographic
        # ellipsis: it is quieter than three full stops and reads as one mark.
        def prompt_path(suffix_length: 0)
          path = Dir.pwd.sub(/\A#{Regexp.escape(Dir.home)}/, "~")
          budget = prompt_path_budget(suffix_length:)
          return path if path.length <= budget

          tail = "#{Aesthetic.wscons? ? '...' : '…'}/#{path.split('/').last(2).join('/')}"
          return tail if tail.length <= budget
          return File.basename(path) if File.basename(path).length <= budget

          path[-budget, budget]
        end

        # Use MASTER's typography contract rather than a second copy of its
        # measure. The prompt borrows its discipline from prose, but the cursor
        # and working path still get priority over a theoretical line length.
        def prompt_path_budget(suffix_length: 0)
          screen = TTY::Screen.width
          target = Master::Design.measure_ideal_ch(root: @config["root"] || Master::ROOT).to_i
          available = screen - suffix_length - 1
          [available, target - suffix_length - 1, PROMPT_PATH_MAX].min
            .clamp(1, PROMPT_PATH_MAX)
        rescue StandardError
          PROMPT_PATH_MAX
        end

        def visible_length(text)
          text.to_s.gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, "").length
        rescue StandardError
          text.to_s.length
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

        # The URL, never the token: a boot line lives in scrollback and saved
        # transcripts, and a link carrying the token is the credential itself.
        # A device gets in through a pairing code.
        def splash_web_url
          url = @config["web_public_url"] || Master::Ground::Config::DEFAULTS.fetch("web_public_url")
          @config["web_token"].to_s.empty? ? url : "#{url}, token set, /pair issue for a code"
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
            d(pledge_line),
          ]
        end

        def model_device_lines(context)
          [
            d("model0 at mainbus0: #{short_model(context[:model])}"),
            d("model0: #{provider_for(context[:model])}, " \
              "#{token_label(Master.context_window(context[:model]))} context"),
          ]
        end

        # dmesg ends where the system starts: the root device, then how long it
        # took to get there.
        def root_on_line(context)
          d("root on master0 (#{context[:revision]}) boot #{monotonic_milliseconds - @boot_ms}ms")
        end

        def git_prompt_segments
          ahead, behind = git_ahead_behind
          dirty = git_dirty?
          branch = git_branch || "detached"
          parts = [dirty ? "#{branch}*" : branch]
          parts << "+#{ahead}" if ahead.positive?
          parts << "-#{behind}" if behind.positive?
          label = parts.join(" ")
          return d(label) if Aesthetic.wscons?
          dirty ? @p.red(label) : @p.dim(label)
        end

        def phase_label(phase)
          phase && phase.to_s != "idle" ? phase_tinted(phase.to_s, phase) : ""
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

        # dmesg names a device it has no driver for as "not configured".
        def pledge_line
          RUBY_PLATFORM.include?("openbsd") ? "pledge0 at mainbus0: armed" : "pledge0 at mainbus0 not configured"
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
