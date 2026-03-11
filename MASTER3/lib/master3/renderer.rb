# frozen_string_literal: true
# encoding: utf-8

require "pastel"

module Master3
  class Renderer
    SEP   = "❯".freeze
    TICK  = "✔".freeze
    CROSS = "✘".freeze

    def initialize(config:)
      @config = config
      @p      = Pastel.new
    end

    def splash(model)
      "\n  #{@p.bold.green("master3")} #{@p.dim(SEP)} #{@p.cyan(model.to_s.split("/").last)}\n"
    end

    alias banner splash

    def prompt_line(model, phase, last_ok: true)
      status = last_ok ? @p.green(SEP) : @p.red(SEP)
      "#{@p.blue(phase.to_s)} #{status} "
    end

    def render(content, mode: :plain)
      case mode
      when :error   then "#{@p.red(CROSS)} #{@p.red(content)}"
      when :success then "#{@p.green(TICK)} #{@p.green(content)}"
      when :warning then "#{@p.yellow("!")} #{@p.yellow(content)}"
      when :dim     then @p.dim(content.to_s)
      else               content.to_s
      end
    end

    def format_error(message)
      render(message, mode: :error)
    end
  end
end
