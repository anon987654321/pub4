# frozen_string_literal: true

require "pastel"

module Master3
  class Renderer
    def initialize(config:)
      @config = config
      @pastel = Pastel.new
    end

    def render(content, mode: :plain)
      case mode
      when :plain    then content.to_s
      when :error    then format_error(content)
      when :success  then @pastel.green(content.to_s)
      when :warning  then @pastel.yellow(content.to_s)
      when :dim      then @pastel.dim(content.to_s)
      when :dmesg    then @pastel.dim(content.to_s)
      else                content.to_s
      end
    end

    def format_error(message)
      lines = message.to_s.split("\n")
      first = @pastel.red("!!  #{lines.first}")
      rest  = lines.drop(1).map { |l| @pastel.dim("    #{l}") }
      ([first] + rest).join("\n")
    end

    def prompt_line(model, phase)
      m = @pastel.cyan(model)
      p = @pastel.dim(phase.to_s)
      "master3 . #{m} . #{p} > "
    end
  end
end
