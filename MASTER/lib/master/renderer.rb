# frozen_string_literal: true
# encoding: utf-8

require "pastel"
require "open3"
require "socket"

module Master
  DEFAULT_WEB_PORT = Config::DEFAULT_WEB_PORT

  class Renderer
    BOOT_DMESG_LINES = 12
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
      t0    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      now   = Time.now
      host  = (Socket.gethostname rescue "openbsd")
      user  = ENV["USER"] || "dev"
      shell = File.basename(ENV["SHELL"] || "zsh")
      pchar = shell == "zsh" ? "%" : "$"
      rev   = git_rev || "1"
      url   = @config["web_public_url"] || "https://ai.brgen.no"
      token = @config["web_token"]
      web   = token ? "#{url}/?token=#{token}" : url
      pledge_ok = RUBY_PLATFORM.include?("openbsd")

      lines = []
      lines << ""
      dmesg_lines.each { |l| lines << @p.dim(l) }
      lines << ""
      lines << d("MASTER (CONSTITUTIONAL) ##{rev}: #{now.strftime('%a %b %e %H:%M:%S %Z %Y')}")
      lines << d("    #{user}@#{host}:#{@config["root"] || Dir.pwd}")
      lines << d("runtime0:  #{RUBY_PLATFORM}  ruby #{RUBY_VERSION}  #{shell} #{user}#{pchar}")
      lines << d("model0:    #{short_model(model)} (#{provider_for(model)})")
      lines << d("rev0:      #{rev}")
      lines << d("security0: #{pledge_ok ? "pledge armed" : "pledge unavailable"}")
      lines << d("web0:      #{web}")
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * MS_PER_SEC).round
      lines << d("boot0:     #{elapsed}ms")
      lines << ""
      lines << @p.bold.red("master") + @p.dim("@#{host} ready")
      lines << ""
      lines.join("\n")
    end

    alias banner splash

    def prompt_line(model, phase, last_ok: true, violations: 0, tokens: nil, cost: nil)
      branch     = git_branch || "detached"
      bar        = token_bar(tokens)
      usage      = token_label(tokens)
      model_str  = @p.dim(short_model(model))
      branch_str = @p.red(branch)
      vbadge     = violations > 0 ? @p.red("[#{violations}v]") : @p.dim("[0v]")
      phase_str  = phase && phase.to_s != "idle" ? phase_tinted(" :#{phase}", phase) : ""
      cost_str   = cost_label(cost)
      cost_seg   = cost_str.empty? ? "" : "#{cost_str} "
      prompt     = phase_prompt(last_ok, phase)
      ["#{branch_str}  #{model_str}  ↖ #{bar}#{usage}  #{cost_seg}#{vbadge}#{phase_str}", prompt + " "]
    end

    def phase_tinted(text, phase)
      case phase.to_s
      when "discover"  then @p.dim.yellow(text)
      when "implement" then @p.dim.cyan(text)
      when "audit"     then @p.dim.red(text)
      else                  @p.dim(text)
      end
    end

    def phase_prompt(last_ok, phase)
      base = "master$"
      return @p.red(base) unless last_ok
      case phase.to_s
      when "discover"  then @p.bold.yellow(base)
      when "implement" then @p.bold.cyan(base)
      when "audit"     then @p.bold.red(base)
      else                  @p.bold.red(base)
      end
    end

    def cost_label(cost)
      cents = (cost.to_f * 100).round(2)
      return "" if cents.zero?
      @p.dim("¢#{format('%.2f', cents)}")
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
      text = beautify(content.to_s)
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
    rescue StandardError
      nil
    end

    def beautify(text)
      text
        .gsub(/"([^"]*?)"/) { "\u201C#{Regexp.last_match(1)}\u201D" }
        .gsub(/\s--\s/, " \u2014 ")
        .gsub(/(\d)-(\d)/, "\\1\u2013\\2")
        .gsub("...", "\u2026")
    end

    private

    def d(text) = @p.dim(text)

    def git_rev
      out, _, st = Open3.capture3("git", "-C", @config["root"] || Dir.pwd, "rev-parse", "--short", "HEAD")
      st.success? ? out.strip : nil
    rescue StandardError
      nil
    end

    def short_model(model)
      model.to_s.sub(/\Aclaude-cli:/, "").sub(/\Aweb-chat:/, "").split("/").last.sub(/:free$/, "")
    end

    def provider_for(model)
      m = model.to_s
      return "claude-cli" if m.start_with?("claude-cli:")
      return "web-chat"   if m.start_with?("web-chat:")
      return "ollama"     if m.start_with?("ollama:", "ollama/")
      return "openrouter" if m.include?("/")
      return "deepseek"   if m.start_with?("deepseek-")
      return "google"     if m.include?("gemini")
      "openrouter"
    end

    def git_branch
      out, _, st = Open3.capture3("git", "rev-parse", "--abbrev-ref", "HEAD")
      st.success? ? out.strip : nil
    rescue StandardError
      nil
    end

    def dmesg_lines
      boot_log = "/var/run/dmesg.boot"
      raw = if File.readable?(boot_log)
              File.readlines(boot_log, chomp: true)
            else
              stdout, = Open3.capture3("dmesg")
              stdout.lines(chomp: true)
            end
      filtered = raw.reject { |l| l.match?(/\A(?:OpenBSD\s+\d|Copyright\s|The Regents)/) }
      lines = filtered.first(BOOT_DMESG_LINES)
      lines.empty? ? ["dmesg unavailable"] : lines
    rescue StandardError
      ["dmesg unavailable"]
    end
  end
end
