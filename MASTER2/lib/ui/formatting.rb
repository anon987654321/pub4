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
      puts "\n  #{bold(title)}"
      puts "  #{'-' * width}"
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
      return false if ENV["NO_COLOR"]
      return false if ENV["TERM"] == "dumb"
      true
    end

    # Color delegate methods - return colored strings without printing
    def yellow(msg)
      pastel.yellow(msg)
    end

    def green(msg)
      pastel.green(msg)
    end

    def red(msg)
      pastel.red(msg)
    end

    def cyan(msg)
      pastel.cyan(msg)
    end

    def magenta(msg)
      pastel.magenta(msg)
    end

    def blue(msg)
      pastel.blue(msg)
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
