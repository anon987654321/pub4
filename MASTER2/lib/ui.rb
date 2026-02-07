# frozen_string_literal: true

# UI - Unified terminal interface using TTY toolkit
# Lazy-loads components for fast startup

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

    def prompt
      @prompt ||= begin
        require "tty-prompt"
        TTY::Prompt.new(symbols: { marker: "›" }, active_color: :cyan)
      end
    end

    def spinner(message = nil, format: :dots)
      require "tty-spinner"
      TTY::Spinner.new("[:spinner] #{message}", format: format)
    end

    def table(data, header: nil)
      require "tty-table"
      TTY::Table.new(header: header) { |t| data.each { |row| t << row } }
    end

    def box(content, title: nil, **opts)
      require "tty-box"
      TTY::Box.frame(content, title: title ? { top_left: " #{title} " } : nil, padding: [0, 1], border: :round, **opts)
    end

    def markdown(text, width: nil)
      require "tty-markdown"
      TTY::Markdown.parse(text, width: width || screen_width)
    end

    def progress(total)
      require "tty-progressbar"
      TTY::ProgressBar.new("[:bar] :percent", total: total)
    end

    def cursor
      @cursor ||= begin
        require "tty-cursor"
        TTY::Cursor
      end
    end

    def reader
      @reader ||= begin
        require "tty-reader"
        TTY::Reader.new
      end
    end

    def pastel
      @pastel ||= begin
        require "pastel"
        Pastel.new(enabled: color_enabled?)
      end
    end

    def color_enabled?
      return false if ENV["NO_COLOR"]
      return false if ENV["TERM"] == "dumb"
      true
    end

    def screen_width
      require "tty-screen"
      TTY::Screen.width rescue 80
    end

    def screen_height
      require "tty-screen"
      TTY::Screen.height rescue 24
    end

    # Convenience methods
    def success(msg) = puts pastel.green("✓ #{msg}")
    def error(msg)   = puts pastel.red("✗ #{msg}")
    def warn(msg)    = puts pastel.yellow("⚠ #{msg}")
    def info(msg)    = puts pastel.cyan("ℹ #{msg}")
    def dim(msg)     = pastel.dim(msg)
    def bold(msg)    = pastel.bold(msg)

    def with_spinner(message)
      s = spinner(message)
      s.auto_spin
      result = yield
      s.success
      result
    rescue StandardError
      s.error
      raise
    end

    def select(question, choices)
      prompt.select(question, choices, cycle: true)
    end

    def confirm(question, default: true)
      prompt.yes?(question, default: default)
    end

    def ask(question, default: nil)
      prompt.ask(question, default: default)
    end

    def render_response(text)
      markdown(text) rescue text
    end
  end
end
