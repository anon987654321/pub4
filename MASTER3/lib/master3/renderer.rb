# frozen_string_literal: true
# encoding: utf-8

require "pastel"

module Master3
  class Renderer
    CHEVRON = "\u276F".freeze

    def initialize(config:)
      @config = config
      @p      = Pastel.new
    end

    def render(content, mode: :plain)
      case mode
      when :plain   then content.to_s
      when :error   then format_error(content)
      when :success then @p.green(content.to_s)
      when :warning then @p.yellow(content.to_s)
      when :dim     then @p.dim(content.to_s)
      when :dmesg   then @p.dim(content.to_s)
      else               content.to_s
      end
    end

    def format_error(message)
      lines = message.to_s.split("\n")
      first = @p.red("\!\!  #{lines.first}")
      rest  = lines.drop(1).map { |l| @p.dim("    #{l}") }
      ([first] + rest).join("\n")
    end

    def prompt_line(model, phase, last_ok: true)
      chevron = last_ok ? @p.magenta(CHEVRON) : @p.red(CHEVRON)
      "#{@p.cyan(phase.to_s)} #{chevron} #{@p.dim(model.to_s.split("/").last)} "
    end

    def banner(model)
      @p.dim("master3 at session0: #{model.to_s.split("/").last}")
    end
  end
end
