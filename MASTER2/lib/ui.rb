# frozen_string_literal: true

# UI - Unified terminal interface using TTY toolkit
# Lazy-loads components for fast startup

module MASTER
  module UI
    extend self

    # --- Typography Icons (minimal vocabulary per Strunk & White) ---
    ICONS = {
      success: "✓",
      failure: "✗",
      warning: "!",
      bullet: "·",
      arrow: "→",
      thinking: "◐",
      done: "●",
    }.freeze

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
      ICONS[name.to_sym] || "·"
    end

    def status(prefix, message, success: true)
      i = success ? icon(:success) : icon(:failure)
      "#{prefix}: #{message} #{i}"
    end

    def progress_line(current, total, message = nil)
      msg = message ? " #{message}" : ""
      "  [#{current}/#{total}]#{msg}"
    end

    def prompt
      @prompt ||= begin
        require "tty-prompt"
        TTY::Prompt.new(symbols: { marker: "›" }, active_color: :cyan)
      rescue LoadError
        nil
      end
    end

    def spinner(message = nil, format: :dots)
      require "tty-spinner"
      TTY::Spinner.new("[:spinner] #{message}", format: format)
    rescue LoadError
      # Fallback: simple inline status
      Object.new.tap do |s|
        s.define_singleton_method(:auto_spin) { print "  #{message}..." }
        s.define_singleton_method(:success) { |msg = "done"| puts " #{msg}" }
        s.define_singleton_method(:error) { |msg = "error"| puts " #{msg}" }
        s.define_singleton_method(:stop) { puts }
      end
    end

    def table(data, header: nil)
      require "tty-table"
      TTY::Table.new(header: header) { |t| data.each { |row| t << row } }
    rescue LoadError
      lines = []
      lines << header.join(" | ") if header
      data.each { |row| lines << row.join(" | ") }
      lines.join("\n")
    end

    def box(content, title: nil, **opts)
      # No box art - just indented content with optional title
      lines = []
      lines << bold(title) if title
      lines << ""
      content.each_line { |l| lines << "  #{l.rstrip}" }
      lines << ""
      lines.join("\n")
    end

    def markdown(text, width: nil)
      require "tty-markdown"
      TTY::Markdown.parse(text, width: width || screen_width)
    rescue LoadError
      text
    end

    def progress(total)
      require "tty-progressbar"
      TTY::ProgressBar.new("[:bar] :percent", total: total)
    rescue LoadError
      Object.new.tap do |p|
        p.instance_variable_set(:@current, 0)
        p.instance_variable_set(:@total, total)
        p.define_singleton_method(:advance) { |n = 1| @current += n; print "\r  [#{@current}/#{@total}]" }
        p.define_singleton_method(:finish) { puts " done" }
      end
    end

    def cursor
      @cursor ||= begin
        require "tty-cursor"
        TTY::Cursor
      rescue LoadError
        Module.new do
          def self.hide; ""; end
          def self.show; ""; end
          def self.move_to(x, y); ""; end
          def self.clear_line; "\r"; end
        end
      end
    end

    def reader
      @reader ||= begin
        require "tty-reader"
        TTY::Reader.new
      rescue LoadError
        nil
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
