# frozen_string_literal: true
# encoding: utf-8

require "pastel"
require "socket"
require_relative "renderer/git_status"
require_relative "renderer/system_info"

module Master
  module Voice
    DEFAULT_WEB_PORT = Ground::Config::DEFAULT_WEB_PORT

    class Renderer
      include GitStatus
      include SystemInfo

      BOOT_DMESG_LINES = 5
      MS_PER_SEC = 1000
      TOKEN_BUDGET = 8000
      BAR_CELLS = 12

      def initialize(config:)
        @config = config
        @p = Pastel.new
        @boot_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * MS_PER_SEC).to_i
      end

      def session_line(name)
        label = @p.dim("session0: ")
        tag = @p.dim.underline(name.to_s.downcase)
        label + tag
      end

      def uptime
        s = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * MS_PER_SEC).to_i - @boot_ms) / MS_PER_SEC
        h, rem = s.divmod(3600)
        m, _ = rem.divmod(60)
        h > 0 ? "up #{h}h#{m}m" : "up #{m}m"
      end

      def splash(model)
        now = Time.now
        host = (Socket.gethostname rescue "openbsd")
        user = ENV["USER"] || "dev"
        shell = File.basename(ENV["SHELL"] || "zsh")
        pchar = shell == "zsh" ? "%" : "$"
        rev = git_rev || "1"
        url = @config["web_public_url"] || "https://ai.brgen.no"
        token = @config["web_token"]
        web = token ? "#{url}/?token=#{token}" : url
        pledge_ok = RUBY_PLATFORM.include?("openbsd")
        dl = dmesg_lines

        lines = []
        lines << ""
        unless dl == ["dmesg unavailable"]
          dl.each { |l| lines << @p.dim(l) }
          lines << ""
        end
        lines << d("MASTER (CONSTITUTIONAL) ##{rev}: #{now.strftime('%a %b %e %H:%M:%S %Z %Y')}")
        lines << d("    #{user}@#{host}:#{@config["root"] || Dir.pwd}")
        lines << d("runtime0: #{RUBY_PLATFORM} ruby #{RUBY_VERSION} #{shell} #{user}#{pchar}")
        lines << d("model0: #{short_model(model)}")
        lines << d("rev0: #{rev}")
        lines << d("soul0: #{soul_version}")
        lines << d("imports0: #{imports_loaded.join(" ")}")
        lines << d("orders0: #{active_orders_count} active")
        lines << d("security0: #{pledge_ok ? "pledge armed" : "pledge unavailable"}")
        lines << d("web0: #{web}")
        lines << d("modules0: ground trace voice now loop judge reach ok")
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * MS_PER_SEC).to_i - @boot_ms)
        lines << d("boot0: #{elapsed}ms")
        lines << ""
        lines << @p.bold.red("master") + @p.dim("@#{host} ready")
        lines << ""
        lines.join("\n")
      end

      alias banner splash

      def prompt_line(model, phase, last_ok: true, violations: 0, tokens: nil, cost: nil)
        branch = git_branch || "detached"
        dirty = git_dirty?
        ahead, behind = git_ahead_behind
        bar = token_bar(tokens)
        usage = token_label(tokens)
        model_str = @p.dim(short_model(model))
        dirty_glyph = dirty ? @p.red("●") : @p.dim("○")
        ahead_str = ahead > 0 ? @p.dim(" ↑#{ahead}") : ""
        behind_str = behind > 0 ? @p.yellow(" ↓#{behind}") : ""
        branch_str = @p.red(branch) + dirty_glyph + ahead_str + behind_str
        vbadge = violation_badge(violations)
        phase_str = phase && phase.to_s != "idle" ? phase_tinted(" :#{phase}", phase) : ""
        cost_str = cost_label(cost)
        cost_seg = cost_str.empty? ? "" : "#{cost_str} "
        prompt = phase_prompt(last_ok, phase)
        ["#{branch_str}  #{model_str}  ↖ #{bar}#{usage}  #{cost_seg}#{vbadge}#{phase_str}", prompt + " "]
      end

      def phase_tinted(text, phase)
        case phase.to_s
        when "discover" then @p.dim.yellow(text)
        when "implement" then @p.dim.cyan(text)
        when "audit" then @p.dim.red(text)
        when "grind", "polish" then @p.dim.magenta(text)
        when "watch" then @p.dim.blue(text)
        else @p.dim(text)
        end
      end

      def violation_badge(count)
        count = count.to_i
        return @p.green(" [0v]") if count.zero?
        return @p.yellow(" [#{count}v]") if count < 10

        @p.bold.red(" [#{count}v]")
      end

      def phase_prompt(last_ok, phase)
        base = "master$"
        return @p.red(base) unless last_ok
        case phase.to_s
        when "discover" then @p.bold.yellow(base)
        when "implement" then @p.bold.cyan(base)
        when "audit" then @p.bold.red(base)
        when "grind", "polish" then @p.bold.magenta(base)
        when "watch" then @p.bold.blue(base)
        else @p.bold.red(base)
        end
      end

      def cost_label(cost)
        cents = (cost.to_f * 100).round(2)
        return "" if cents.zero?
        budget = @config.respond_to?(:budget_max) ? @config.budget_max.to_f : 0.0
        label = "¢#{format('%.2f', cents)}"
        return @p.dim(label) unless budget.positive?
        pct = (cost.to_f / budget).clamp(0.0, 1.0)
        eighths = (pct * 4 * 8).round
        full = eighths / 8
        rem  = eighths % 8
        bar = ("\u2588" * full) + (full < 4 ? BAR_FRACTIONS[rem] : "") + ("\u00A0" * (4 - full - (full < 4 ? 1 : 0)))
        @p.dim("#{label} #{bar}")
      end

      def speaker_tag(name = "master")
        "#{@p.dim("<")}#{@p.bold.red(name)}#{@p.dim(">")}"
      end

      def status_row(uptime:, turns:, violations: 0)
        bits = ["stat0:", uptime, "#{turns} turns"]
        bits << "#{violations}v" if violations > 0
        @p.dim(bits.join(" "))
      end

      BAR_FRACTIONS = ["\u00A0", "\u258F", "\u258E", "\u258D", "\u258C", "\u258B", "\u258A", "\u2589", "\u2588"].freeze

      def token_bar(tokens)
        return "" unless tokens && tokens > 0
        budget = (@config["token_budget"] || TOKEN_BUDGET).to_i
        pct    = (tokens.to_f / budget).clamp(0.0, 1.0)
        eighths = (pct * BAR_CELLS * 8).round
        full   = eighths / 8
        rem    = eighths % 8
        bar    = ("\u2588" * full)
        bar   += BAR_FRACTIONS[rem] if full < BAR_CELLS
        bar   += "\u00A0" * (BAR_CELLS - full - (full < BAR_CELLS ? 1 : 0))
        @p.dim(bar) + " "
      end

      def token_label(tokens)
        return "0" unless tokens && tokens > 0
        value = tokens.to_i
        value >= 1000 ? format("%.1fk", value / 1000.0) : value.to_s
      end

      def render(content, mode: :plain)
        text = output_guard.sanitize(beautify(content.to_s), context: output_context(mode))
        case mode
        when :error   then @p.red("err: #{text}")
        when :success then @p.bright_red("ok: #{text}")
        when :warning then @p.red("warn: #{text}")
        when :dim     then @p.dim(text)
        when :dmesg   then format_dmesg(text)
        else text
        end
      end

      def format_error(message) = render(message, mode: :error)
      def format_dmesg(line) = @p.dim(line.to_s)

      def closing
        path = File.join(Master::ROOT, "data", "closings.yml")
        lines = (Master.load_yaml(path) || {})["closings"]
        return nil unless lines.is_a?(Array) && lines.any?
        @p.dim(lines.sample)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "renderer.closing")
        nil
      end

      def beautify(text)
        text
          .gsub(/"([^"]*?)"/) { "\u201C#{Regexp.last_match(1)}\u201D" }
          .gsub(/\s--\s/, " \u2014 ")
          .gsub(/(\d)-(\d)/, "\\1\u2013\\2")
          .gsub("...", "\u2026")
      end

      def output_guard
        @output_guard ||= Master::Voice::OutputGuard.new
      end

      def output_context(mode)
        case mode
        when :dmesg, :diag then :diagnostic
        when :success then :completion
        when :error then :diagnostic
        else :routine
        end
      end

      private

      def d(text) = @p.dim(text)
    end
  end
end
