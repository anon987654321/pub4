# frozen_string_literal: true
# encoding: utf-8

require "pastel"
require "open3"

module Master
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
      lines << "#{@p.bold.red("master")}@#{@p.red(short_model(model))} #{@p.dim("ready")}"
      lines << @p.dim("web  http://brgen.no:3000")
      lines << ""
      lines.join("\n")
    end

    alias banner splash

    def prompt_line(model, phase, last_ok: true)
      dollar = last_ok ? @p.bright_red("$") : @p.red("$")
      "#{@p.bold.red("master")}@#{@p.red(short_model(model))}#{dollar} "
    end

    def render(content, mode: :plain)
      case mode
      when :error   then "#{@p.red(CROSS)} #{@p.red(content)}"
      when :success then "#{@p.bright_red(TICK)} #{@p.bright_red(content)}"
      when :warning then "#{@p.red("\!")} #{@p.red(content)}"
      when :dim     then @p.dim(content.to_s)
      when :dmesg   then format_dmesg(content)
      else               content.to_s
      end
    end

    def format_error(message)
      render(message, mode: :error)
    end

    def format_dmesg(line)
      @p.dim("[#{elapsed_ms}] #{line}")
    end

    private

    def short_model(model)
      model.to_s.split("/").last
    end

    def dmesg_lines
      stdout, _stderr, _status = Open3.capture3("dmesg")
      raw = stdout.lines.first(18).map(&:chomp)
      raw.empty? ? ["dmesg unavailable"] : raw
    rescue StandardError
      ["dmesg unavailable"]
    end

    def elapsed_ms
      @start_ms ||= (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
      now = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
      format("%d.%03d", (now - @start_ms) / 1000, (now - @start_ms) % 1000)
    end
  end
end
