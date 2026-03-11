# frozen_string_literal: true
# encoding: utf-8

require "pastel"

module Master3
  class Renderer
    TICK  = "✔".freeze
    CROSS = "✘".freeze

    def initialize(config:)
      @config = config
      @p      = Pastel.new
    end

    def splash(model)
      lines = []
      lines << ""
      dmesg_lines.each { |l| lines << @p.dim(l) }
      lines << ""
      lines << "#{@p.bold.green("master3")}@#{@p.cyan(short_model(model))} ready"
      lines << ""
      lines.join("\n")
    end

    alias banner splash

    def prompt_line(model, phase, last_ok: true)
      dollar = last_ok ? @p.green("$") : @p.red("$")
      "#{@p.bold.green("master3")}@#{@p.cyan(short_model(model))}#{dollar} "
    end

    def render(content, mode: :plain)
      case mode
      when :error   then "#{@p.red(CROSS)} #{@p.red(content)}"
      when :success then "#{@p.green(TICK)} #{@p.green(content)}"
      when :warning then "#{@p.yellow("!")} #{@p.yellow(content)}"
      when :dim     then @p.dim(content.to_s)
      when :dmesg   then format_dmesg(content)
      else               content.to_s
      end
    end

    def format_error(message)
      render(message, mode: :error)
    end

    # Format internal log lines like OpenBSD dmesg
    def format_dmesg(line)
      @p.dim("[#{elapsed_ms}] #{line}")
    end

    private

    def short_model(model)
      model.to_s.split("/").last
    end

    def dmesg_lines
      raw = `dmesg 2>/dev/null`.lines.first(18).map(&:chomp)
      raw.empty? ? ["dmesg unavailable"] : raw
    rescue
      ["dmesg unavailable"]
    end

    def elapsed_ms
      @start_ms ||= (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
      now = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
      format("%d.%03d", (now - @start_ms) / 1000, (now - @start_ms) % 1000)
    end
  end
end
