# frozen_string_literal: true

module MASTER
  module UI
    extend self

    # --- Formatting Helpers (DRY) ---
    def currency(n)
      format("$%.2f", n)
    end

    def currency_precise(n)
      format("$%.4f", n)
    end

    def truncate_id(id, len = 8)
      "#{id[0, len]}..."
    end

    def header(title, width: 40)
      puts bold(title)
    end

    def icon(name)
      ICONS[name.to_sym] || "."
    end

    def render_bar(pct, width: 30)
      filled = (pct / 100.0 * width).round
      "[#{'#' * filled}#{'.' * (width - filled)}]"
    end

    def status(prefix, message, success: true)
      i = success ? icon(:success) : icon(:failure)
      "#{prefix}: #{message} #{i}"
    end

    def progress_line(current, total, message = nil)
      msg = message ? " #{message}" : ""
      "  [#{current}/#{total}]#{msg}"
    end

    def color_enabled?
      return false unless $stdout.tty?
      return false if ENV["NO_COLOR"]
      return false if ENV["TERM"] == "dumb"
      true
    end

    # Color delegate methods - return colored strings without printing
    # Define color methods dynamically to reduce duplication
    %i[yellow green red cyan magenta blue].each do |color|
      define_method(color) do |msg|
        pastel.public_send(color, msg)
      end
    end

    def colorize(text)
      return text unless color_enabled?
      text
        .gsub(/^(MASTER .+)$/) { pastel.bold($1) }
        .gsub(/^(\w+) at (\w+):(.*)/) { "#{pastel.blue($1)} at #{pastel.cyan($2)}:#{$3}" }
        .gsub(/(\d+) (axioms|personas|stages)/) { "#{pastel.bright_magenta($1)} #{$2}" }
        .gsub(/(\$[\d.]+)/) { pastel.bright_cyan($1) }
        .gsub(/(armed|ok)\b/) { pastel.green($1) }
        .gsub(/(unavailable|error|FAIL)\b/) { pastel.red($1) }
        .gsub(/(\d+ms)$/) { pastel.bright_black($1) }
    end
  end
end
