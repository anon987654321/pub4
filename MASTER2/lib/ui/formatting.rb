# frozen_string_literal: true

module MASTER
  module UI
    module_function

    def currency(n)
      format("$%.2f", n)
    end

    def currency_precise(n)
      format("$%.4f", n)
    end

    def truncate_id(id, len = 8)
      id.length > len ? "#{id[0, len]}#{ICONS[:ellipsis]}" : id
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
      status_icon = success ? icon(:success) : icon(:failure)
      "#{prefix}: #{message} #{status_icon}"
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
    %i[yellow red blue white bright_black].each do |color|
      define_method(color) do |msg|
        pastel.public_send(color, msg)
      end
    end

    def colorize(text)
      return text unless color_enabled?

      text
        .gsub(/^(MASTER .+)$/) { pastel.bold.white(::Regexp.last_match(1)) }
        .gsub(/^(    .+)$/) { pastel.bright_black(::Regexp.last_match(1)) }
        .gsub(/^(\w+0):(.*)$/) { "#{pastel.blue(::Regexp.last_match(1))}:#{::Regexp.last_match(2)}" }
        .gsub(/(\d+) (axioms?|personas?|stages?)/) { "#{pastel.white(::Regexp.last_match(1))} #{::Regexp.last_match(2)}" }
        .gsub(/(armed|ok)\b/) { pastel.bold.white(::Regexp.last_match(1)) }
        .gsub(/(unavailable|error|FAIL)\b/) { pastel.red(::Regexp.last_match(1)) }
        .gsub(/(\d+ms)$/) { pastel.bright_black(::Regexp.last_match(1)) }
    end

    # "1 axiom" / "3 axioms" — never "1 axioms"
    def pluralize(n, word)
      "#{n} #{n == 1 ? word : "#{word}s"}"
    end

    # "12.3%" — single decimal, consistent everywhere
    def format_percent(n)
      format("%.1f%%", n.to_f)
    end

    # "1.2k" for thousands, plain integer otherwise
    def format_number(n)
      n = n.to_i
      n >= 1_000 ? format("%.1fk", n / 1_000.0) : n.to_s
    end
  end
end
