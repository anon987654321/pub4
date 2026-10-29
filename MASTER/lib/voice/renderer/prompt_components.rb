# frozen_string_literal: true

require "tty-screen"
require_relative "../../face"

module Master
  module Voice
    class Renderer
      # Splash and prompt rendering — separate from Renderer's own
      # render/output-guard responsibility.
      #
      # The splash and operational status use the OpenBSD dmesg idiom: plain,
      # factual lines with stable unit names. The prompt is deliberately smaller:
      # location, Git state, phase and textual input state without decoration.
      module PromptComponents
        TOKEN_KILO_THRESHOLD = 1000
        PROMPT_PATH_MAX = 44
        PROMPT_GIT_CACHE_S = 0.25
        PROMPT_MAX_CHARS = Master::Face::Contract.prompt_max
        PROMPT_MEASURE_CH = Master::Face::Contract.prompt_measure
        ANSI_ESCAPE = /\e\[[0-9;?]*[ -\/]*[@-~]/
        def splash(model)
          context = splash_context(model)
          text = if verbose_boot?
                   lines = [*identity_lines(context), *splash_dmesg_lines, *device_lines_for(context),
                            root_on_line(context)]
                   host_status = Master::Ground::HostBudget.status_line
                   lines << d(host_status) if host_status
                   lines.join("\n")
                 else
                   compact_splash(context)
                 end
          boot_surface(text)
        end
        alias banner splash

        def verbose_boot?
          return false if ENV["MASTER_QUIET"] == "1"
          return false if %w[0 quiet].include?(ENV["MASTER_DMESG"].to_s.downcase)

          ENV["MASTER_BOOT_STATUS"] == "1" ||
            ENV["MASTER_CLI_VERBOSE"] == "1" ||
            ENV["MASTER_CLI_TRACE"] == "1"
        end

        def compact_splash(context)
          model = short_model(context[:model])
          web = if splash_web_url.to_s.include?("http")
                  @config["web_token"].to_s.empty? ? "ready" : "ready, token set, /pair issue for a code"
                else
                  "not configured"
                end
          speech_error = Master::Voice::Speech.last_error if defined?(Master::Voice::Speech)
          playback_error = Master::Voice::Playback.last_error if defined?(Master::Voice::Playback)
          voice_reason = [speech_error, playback_error].compact.map(&:to_s).reject(&:empty?).first
          voice = ENV["MASTER_TTS_DEGRADED"] == "1" || voice_reason ? "degraded" : "ready"
          [
            d("master0 at mainbus0: MASTER #{release_version} ##{context[:build]}, model #{model}"),
            d("host0 at mainbus0: #{context[:user]}@#{context[:host]}:#{@config['root'] || Dir.pwd}"),
            d("voice0 at mainbus0: #{voice}"),
            d("web0 at mainbus0: #{web}"),
            *radio_lines,
            d("root on master0"),
          ].join("\n")
        rescue StandardError
          [
            d("master0 at mainbus0: MASTER #{release_version}"),
            d("host0 at mainbus0: #{context[:user]}@#{context[:host]}"),
            d("voice0 at mainbus0: unknown"),
            d("root on master0"),
          ].join("\n")
        end

        # net0 and bth0, as a kernel prints its radios; patterns.yml cli.boot_devices: false leaves them out.
        def radio_lines
          return [] unless Master.patterns_config.fetch("cli", {})["boot_devices"] == true

          Master::CLI::BootDevices.lines.map { |line| d(line) }
        end

        # [state line or nil, prompt]. The state line carries what a status bar
        # used to: the caller prints it only when one of its values moves.
        def prompt_line(model, phase, **options)
          last_ok = options.fetch(:last_ok, true)
          destination = options.fetch(:destination, "llm")
          focused = options.fetch(:focused, false)
          operator = operator_state(phase, last_ok, destination:, focused:)

          [
            state_line(model, **options.merge(operator:)),
            shell_prompt(phase, last_ok, destination:, focused:),
          ]
        end

        def state_line(model, **options)
          name = short_model(model)
          bits = [options[:operator], name.empty? ? "no model" : name,
                  context_label(options[:tokens], model)].compact
          violations = options.fetch(:violations, 0).to_i
          bits << "#{violations} violations" if violations.positive?
          d(bits.join(", "))
        end

        def phase_tinted(text, _phase)
          text.to_s
        end

        def prompt_token
          File.basename(ENV["SHELL"].to_s) == "zsh" ? "%" : "$"
        end

        def phase_prompt(last_ok, _phase)
          last_ok ? "input" : "error input"
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

        def boot_surface(text)
          text.to_s.gsub(ANSI_ESCAPE, "")
        end

        # One stable OpenBSD-style input prompt; changing context is announced
        # separately only when it changes, so the editable line stays familiar.
        def shell_prompt(_phase, _last_ok, **)
          prompt = Master::Face::Contract.shell_prompt(
            path: Dir.pwd,
            host: safe_hostname.to_s,
            root: @config["root"] || Master::ROOT,
          )
          "#{prompt} "
        end

        def operator_state(phase, last_ok, destination:, focused:)
          words = [bounded_prompt_segment(git_prompt_text, 16), prompt_destination(destination)]
          words << bounded_prompt_segment(phase_label(phase), 10) unless focused
          words << "error" unless last_ok
          words.reject(&:empty?).join(" ")
        end

        def prompt_host
          host = bounded_prompt_segment(safe_hostname.to_s.split(".").first, 8)
          host.empty? ? "openbsd" : host
        end

        def prompt_suffix(phase, last_ok, destination:, focused:)
          phase_text = focused ? "" : bounded_prompt_segment(phase_label(phase), 10)
          git = bounded_prompt_segment(git_prompt_text, 16)

          [git, prompt_destination(destination), phase_text, phase_prompt(last_ok, phase)].reject(&:empty?)
        end

        def prompt_destination(value)
          destination = plain_prompt_segment(value)
          destination = "llm" if destination.empty?
          bounded_prompt_segment(destination, 22)
        rescue StandardError
          "llm"
        end

        def plain_prompt_segment(value)
          value.to_s.scrub.gsub(ANSI_ESCAPE, "").unicode_normalize(:nfc)
            .gsub(/[^\p{L}\p{N}]+/u, " ").strip.gsub(/\s+/, " ")
        rescue StandardError
          ""
        end

        def bounded_prompt_segment(value, width)
          text = plain_prompt_segment(value)
          return text if text.length <= width

          text[0, width].strip
        end

        # Keep raw path lookup filesystem-aware and bounded. The rendered prompt
        # normalizes punctuation into word spacing to keep its plain-text contract.
        def prompt_path(suffix_length: 0)
          current = File.expand_path(Dir.pwd)
          location = repository_location(current) || home_path(current)
          budget = prompt_path_budget(suffix_length:)
          return location if location.length <= budget

          if (prefix = repository_path_prefix(current))
            tail = repository_relative_path(current).to_s.split("/").reject(&:empty?).last(2)
            candidates = []
            candidates << "#{prefix}/.../#{tail.join("/")}" if tail.length == 2
            candidates << "#{prefix}/.../#{tail.last}" if tail.any?
            candidates << prefix
            return candidates.find { |candidate| candidate.length <= budget } || prefix[0, budget]
          end

          tail = ".../#{location.split('/').last(2).join('/')}"
          return tail if tail.length <= budget
          return File.basename(location) if File.basename(location).length <= budget

          location[-budget, budget]
        end

        # Within pub4, identify both the checkout and its governed tree. A
        # truncated path must preserve that prefix and the directory being used.
        def repository_location(path)
          relative = repository_relative_path(path)
          return unless relative

          root_name = File.basename(Master.repo_root)
          relative.empty? ? root_name : "#{root_name}/#{relative}"
        end

        def repository_relative_path(path)
          root = File.expand_path(Master.repo_root)
          current = File.expand_path(path)
          return "" if current == root
          return unless current.start_with?("#{root}/")

          current.delete_prefix("#{root}/")
        end

        def repository_path_prefix(path)
          relative = repository_relative_path(path)
          return unless relative

          root_name = File.basename(Master.repo_root)
          tree = relative.split("/").first
          tree ? "#{root_name}/#{tree}" : root_name
        end

        def home_path(path)
          home = Dir.home
          return "~" if path == home

          prefix = "#{home}/"
          return "~#{path.delete_prefix(home)}" if path.start_with?(prefix)

          path
        end

        # Use MASTER's typography contract rather than a second copy of its
        # measure. The prompt borrows its discipline from prose, while Reline owns the editing cursor
        # and the current working path keeps priority over a theoretical line length.
        def prompt_path_budget(suffix_length: 0)
          screen = TTY::Screen.width
          contract = Master::Design.face_interface(root: @config["root"] || Master::ROOT)
          target = contract.dig("prompt", "measure_ch").to_i
          target = Master::Design::Thresholds.measure_ideal_ch(root: @config["root"] || Master::ROOT).to_i if target <= 0
          max_ch = contract.dig("prompt", "max_ch").to_i
          max_ch = PROMPT_MAX_CHARS if max_ch <= 0
          available = [screen, max_ch].min - suffix_length - 1
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

        def release_version = Master::VERSION

        def splash_ready_line(context)
          short_host = context[:host].split(".").first
          d("console0 at master0: #{context[:user]}@#{short_host}#{context[:prompt]} ready")
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
            d("master0 at mainbus0: MASTER #{release_version} ##{context[:build]}"),
            d("host0 at mainbus0: #{context[:user]}@#{context[:host]}:#{@config['root'] || Dir.pwd}"),
          ]
        end

        def device_lines_for(context)
          mode = Master::CLI::RuntimeMode.summary(config: @config).split(", ")
          [
            d("release0 at mainbus0: pub4 #{release_version}"),
            d("ruby0 at mainbus0: ruby #{RUBY_VERSION} #{RUBY_PLATFORM}"),
            d("shell0 at mainbus0: #{context[:shell]}, user #{context[:user]}"),
            d("soul0 at mainbus0: constitution rev #{soul_version}"),
            d("soul0: imports #{imports_loaded.join(' ')}"),
            d("soul0: #{active_orders_count} orders active"),
            *model_device_lines(context),
            d("voice0 at mainbus0: #{ENV["MASTER_TTS_DEGRADED"] == "1" ? "degraded" : "ready"}"),
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

        def git_prompt_text
          state = prompt_git_state
          return "" unless state

          branch_status(**state)
        end

        def branch_status(branch:, ahead:, behind:, dirty:)
          branch_name = plain_prompt_segment(branch).split.first.to_s
          branch_name = bounded_prompt_segment(branch_name, 8)
          parts = [branch_name]
          parts << "dirty" if dirty
          [["ahead", ahead], ["behind", behind]].each do |label, count|
            next unless count.positive?

            detail = "#{label} #{count}"
            parts << detail if parts.join(" ").length + detail.length + 1 <= 16
          end
          parts.reject(&:empty?).join(" ")
        end

        def prompt_git_state
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          cwd = Dir.pwd
          if @prompt_git_cache &&
             @prompt_git_cache[:cwd] == cwd &&
             now - @prompt_git_cache[:at] < PROMPT_GIT_CACHE_S
            return @prompt_git_cache[:state]
          end

          state = git_prompt_state
          @prompt_git_cache = { cwd:, at: now, state: }
          state
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "renderer.prompt_git_state")
          nil
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
