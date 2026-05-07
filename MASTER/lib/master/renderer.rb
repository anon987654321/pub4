# frozen_string_literal: true
# encoding: utf-8

require "pastel"
require "open3"
require "socket"

module Master
  DEFAULT_WEB_PORT = Config::DEFAULT_WEB_PORT

  class Renderer
    TICK             = "\u2714".freeze
    CROSS            = "\u2718".freeze
    BOOT_DMESG_LINES = 12
    MS_PER_SEC       = 1000

    def initialize(config:)
      @config   = config
      @p        = Pastel.new
      @boot_ms  = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * MS_PER_SEC).to_i
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

    def prompt_line(model, phase, last_ok: true, violations: 0, tokens: nil)
      branch = git_branch
      tok    = tokens && tokens > 0 ? @p.dim("#{tokens}t ") : ""
      vbadge = violations > 0 ? @p.red("[#{violations}v] ") : ""
      phase_str = phase && phase.to_s != "idle" ? @p.dim("{#{phase}} ") : ""
      branch_str = branch ? "#{@p.dim("(")}#{@p.red(branch)}#{@p.dim(")")} " : ""
      dollar = last_ok ? @p.bright_red("$") : @p.red("$")
      "#{@p.bold.red("master")}@#{@p.red(short_model(model))} #{branch_str}#{phase_str}#{tok}#{vbadge}#{dollar} "
    end

    def render(content, mode: :plain)
      case mode
      when :error   then "#{@p.red(CROSS)} #{@p.red(content)}"
      when :success then "#{@p.bright_red(TICK)} #{@p.bright_red(content)}"
      when :warning then @p.red("! #{content}")
      when :dim     then @p.dim(content.to_s)
      when :dmesg   then format_dmesg(content)
      else               content.to_s
      end
    end

    def format_error(message)  = render(message, mode: :error)
    def format_dmesg(line)     = @p.dim(line.to_s)

    def beautify(text)
      text
        .gsub(/"([^"]*?)"/) { "\u201C#{Regexp.last_match(1)}\u201D" }
        .gsub(/\s--\s/, " \u2014 ")
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
      return "claude-cli"   if m.start_with?("claude-cli:")
      return "web-chat"     if m.start_with?("web-chat:")
      return "ollama"       if m.start_with?("ollama/")
      return "google"       if m.include?("gemini")
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
