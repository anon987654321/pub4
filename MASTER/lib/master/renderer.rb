# frozen_string_literal: true
# encoding: utf-8

require "pastel"
require "open3"
require "socket"

module Master
  DEFAULT_WEB_PORT = Config::DEFAULT_WEB_PORT

  class Renderer
    TICK  = "\u2714".freeze
    CROSS = "\u2718".freeze
    DMESG_LINE_COUNT = 5
    MILLISECONDS_PER_SECOND = 1000

    def initialize(config:)
      @config = config
      @p      = Pastel.new
    end

    def splash(model)
      now   = Time.now
      host  = Socket.gethostname rescue "openbsd"
      ruby  = RUBY_VERSION
      up    = uptime_str
      url   = @config["web_public_url"] || "https://ai.brgen.no"
      mod   = short_model(model)
      rev   = git_rev

      lines = []
      lines << ""
      dmesg_lines.each { |l| lines << @p.dim(l) }
      lines << ""
      lines << @p.bold.red("MASTER") + @p.dim(" constitutional AI agent")
      lines << @p.dim("hostname #{host}  ruby #{ruby}  #{now.strftime('%Y-%m-%d %H:%M:%S')}")
      lines << @p.dim("model    #{mod}")
      lines << @p.dim("web      #{url}")
      lines << @p.dim("rev      #{rev}") if rev
      lines << @p.dim("uptime   #{up}") if up
      lines << ""
      lines << @p.bold.red("master") + @p.dim("@#{host} ready -- type ") + @p.bright_red("help") + @p.dim(" for commands")
      lines << ""
      lines.join("\n")
    end

    alias banner splash

    def prompt_line(model, phase, last_ok: true, violations: 0, tokens: nil)
      branch = git_branch
      tok    = tokens && tokens > 0 ? @p.dim("#{tokens}t ") : ""
      vbadge = violations > 0 ? @p.red("[#{violations}v] ") : ""
      branch_str = branch ? "#{@p.dim("(")}#{@p.red(branch)}#{@p.dim(")")} " : ""
      dollar = last_ok ? @p.bright_red("$") : @p.red("$")
      "#{@p.bold.red("master")}@#{@p.red(short_model(model))} #{branch_str}#{tok}#{vbadge}#{dollar} "
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

    def format_error(message)
      render(message, mode: :error)
    end

    def format_dmesg(line)
      @p.dim(line.to_s)
    end

    private

    def uptime_str
      out, = Open3.capture2e("uptime")
      out = out.strip
      out.empty? ? nil : out.split(",").first.gsub(/.*up\s+/, "").strip
    rescue StandardError => _e
      nil
    end

    def git_rev
      out, _, st = Open3.capture3("git", "-C", @config["root"] || Dir.pwd, "rev-parse", "--short", "HEAD")
      st.success? ? out.strip : nil
    rescue StandardError => _e
      nil
    end

    def short_model(model)
      model.to_s.split("/").last
    end

    def git_branch
      out, _, status = Open3.capture3("git", "rev-parse", "--abbrev-ref", "HEAD")
      status.success? ? out.strip : nil
    rescue StandardError => _e
      nil
    end

    def dmesg_lines
      stdout, _stderr, _status = Open3.capture3("dmesg")
      raw = stdout.lines.first(DMESG_LINE_COUNT).map(&:chomp)
      raw.empty? ? ["dmesg unavailable"] : raw
    rescue StandardError => _e
      ["dmesg unavailable"]
    end

    def elapsed_ms
      @start_ms ||= (Process.clock_gettime(Process::CLOCK_MONOTONIC) * MILLISECONDS_PER_SECOND).to_i
      now = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * MILLISECONDS_PER_SECOND).to_i
      format("%d.%03d", (now - @start_ms) / MILLISECONDS_PER_SECOND, (now - @start_ms) % MILLISECONDS_PER_SECOND)
    end
  end
end