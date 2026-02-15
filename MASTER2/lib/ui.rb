# frozen_string_literal: true

# UI - Unified terminal interface using TTY toolkit
# Lazy-loads components for fast startup
# Restored from MASTER v1 with full TTY integration

module MASTER
  module UI
    extend self

    # Boot time for dmesg-style timestamps
    MASTER_BOOT_TIME = Time.now

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

    # --- TTY Component Lazy Loaders ---

    def prompt
      @prompt ||= begin
        require 'tty-prompt'
        TTY::Prompt.new(symbols: { marker: '›' }, active_color: :cyan)
      rescue LoadError
        nil
      end
    end

    def spinner(message = nil, format: :braille)
      require 'tty-spinner'
      TTY::Spinner.new("[:spinner] #{message}", format: format)
    rescue LoadError
      Object.new.tap do |s|
        s.define_singleton_method(:auto_spin) {}
        s.define_singleton_method(:success) { puts "✓" }
        s.define_singleton_method(:error) { puts "✗" }
      end
    end

    def multi_spinner
      require 'tty-spinner'
      TTY::Spinner::Multi.new("[:spinner] Processing", format: :braille)
    rescue LoadError
      Object.new.tap { |s| s.define_singleton_method(:register) { |*| spinner } }
    end

    def table(data, header: nil)
      require 'tty-table'
      opts = header ? { header: header } : {}
      TTY::Table.new(opts) { |t| data.each { |row| t << row } }
    rescue LoadError
      # Fallback to simple text table
      lines = []
      lines << header.join(" | ") if header
      data.each { |row| lines << row.join(" | ") }
      lines.join("\n")
    end

    def box(content, title: nil, **opts)
      require 'tty-box'
      TTY::Box.frame(
        content,
        title: title ? { top_left: " #{title} " } : nil,
        padding: [0, 1],
        border: :round,
        **opts
      )
    rescue LoadError
      # Fallback to indented content
      lines = []
      lines << bold(title) if title
      lines << ""
      content.each_line { |l| lines << "  #{l.rstrip}" }
      lines << ""
      lines.join("\n")
    end

    def markdown(text, width: nil)
      require 'tty-markdown'
      TTY::Markdown.parse(text, width: width || screen_width)
    rescue LoadError
      text
    end

    def progress(total, format: :bar)
      require 'tty-progressbar'
      TTY::ProgressBar.new(
        "[:bar] :percent :eta",
        total: total,
        bar_format: format == :block ? :block : :classic
      )
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
        require 'tty-cursor'
        TTY::Cursor
      rescue LoadError
        Module.new do
          def self.hide; ""; end
          def self.show; ""; end
          def self.up(n=1); ""; end
          def self.down(n=1); ""; end
          def self.forward(n=1); ""; end
          def self.backward(n=1); ""; end
          def self.column(n); ""; end
          def self.move_to(x, y); ""; end
          def self.clear_line; "\r"; end
          def self.clear_screen; ""; end
        end
      end
    end

    def reader
      @reader ||= begin
        require 'tty-reader'
        TTY::Reader.new
      rescue LoadError
        Object.new.tap do |r|
          r.define_singleton_method(:read_line) { |*| gets }
          r.define_singleton_method(:read_keypress) { $stdin.getch rescue gets }
        end
      end
    end

    def tree(data)
      require 'tty-tree'
      TTY::Tree.new(data)
    rescue LoadError
      # Fallback to simple indented list
      def self.format_tree(data, indent=0)
        return "" unless data.is_a?(Hash) || data.is_a?(Array)
        lines = []
        (data.is_a?(Hash) ? data : data.each_with_index.to_a).each do |k, v|
          lines << "  " * indent + "- #{k}"
          lines << format_tree(v, indent + 1) if v.is_a?(Hash) || v.is_a?(Array)
        end
        lines.join("\n")
      end
      format_tree(data)
    end

    def pie(data)
      require 'tty-pie'
      TTY::Pie.new(data: data, radius: 5)
    rescue LoadError
      # Fallback to simple list
      Object.new.tap do |p|
        p.instance_variable_set(:@data, data)
        p.define_singleton_method(:render) do
          @data.map { |d| "#{d[:name]}: #{d[:value]}" }.join(", ")
        end
      end
    end

    def pager
      @pager ||= begin
        require 'tty-pager'
        TTY::Pager.new
      rescue LoadError
        Object.new.tap do |p|
          p.define_singleton_method(:page) { |text| puts text }
        end
      end
    end

    def link(text, url)
      require 'tty-link'
      TTY::Link.link_to(text, url)
    rescue LoadError
      "#{text} (#{url})"
    end

    def font(text, font_name = :doom)
      require 'tty-font'
      TTY::Font.new(font_name).write(text)
    rescue LoadError
      text
    end

    def edit(path_or_text)
      require 'tty-editor'
      TTY::Editor.open(path_or_text)
    rescue LoadError
      # Fallback to system editor
      editor = ENV['EDITOR'] || 'vi'
      if File.exist?(path_or_text)
        system(editor, path_or_text)
      else
        tmpfile = "/tmp/master_edit_#{Time.now.to_i}.txt"
        File.write(tmpfile, path_or_text)
        system(editor, tmpfile)
        File.read(tmpfile)
      end
    end

    def command(*cmd, **opts)
      require 'tty-command'
      TTY::Command.new(printer: :quiet).run(*cmd, **opts)
    rescue LoadError
      # Fallback to system
      system(*cmd)
    end

    def screen_width
      @screen_width ||= begin
        require 'tty-screen'
        TTY::Screen.width
      rescue LoadError
        80
      end
    end

    def screen_height
      @screen_height ||= begin
        require 'tty-screen'
        TTY::Screen.height
      rescue LoadError
        24
      end
    end

    def platform
      @platform ||= begin
        require 'tty-platform'
        TTY::Platform.new
      rescue LoadError
        Object.new.tap do |p|
          p.define_singleton_method(:os) { RbConfig::CONFIG['host_os'] }
          p.define_singleton_method(:cpu) { RbConfig::CONFIG['host_cpu'] }
          p.define_singleton_method(:arch) { RbConfig::CONFIG['arch'] }
        end
      end
    end

    def which(cmd)
      require 'tty-which'
      TTY::Which.which(cmd)
    rescue LoadError
      # Fallback to simple which
      ENV['PATH'].split(':').each do |dir|
        path = File.join(dir, cmd)
        return path if File.executable?(path)
      end
      nil
    end

    def pastel
      @pastel ||= begin
        require 'pastel'
        Pastel.new(enabled: color_enabled?)
      rescue LoadError
        # Fallback when pastel gem is not available
        Object.new.tap do |p|
          %i[green red yellow cyan dim bold magenta bright_magenta bright_cyan bright_black blue].each do |color|
            p.define_singleton_method(color) { |text = nil| text.nil? ? self : text }
          end
        end
      end
    end

    # --- High-level Convenience Methods ---

    def success(msg)
      puts pastel.green("✓ #{msg}")
    end

    def error(msg)
      puts pastel.red("✗ #{msg}")
    end

    def warn(msg)
      puts pastel.yellow("⚠ #{msg}")
    end

    def info(msg)
      puts pastel.cyan("ℹ #{msg}")
    end

    def dim(msg)
      pastel.dim(msg)
    end

    def bold(msg)
      pastel.bold(msg)
    end

    def with_spinner(message, &block)
      s = spinner(message)
      s.auto_spin
      result = yield
      s.success
      result
    rescue StandardError => e
      s.error
      raise
    end

    def select(question, choices)
      return nil unless prompt
      prompt.select(question, choices, cycle: true)
    end

    def multi_select(question, choices)
      return [] unless prompt
      prompt.multi_select(question, choices, cycle: true)
    end

    def confirm(question, default: true)
      return default unless prompt
      prompt.yes?(question, default: default)
    end

    def ask(question, default: nil)
      return default unless prompt
      prompt.ask(question, default: default)
    end

    def paginate(text)
      pager.page(text)
    end

    def clear_line
      print cursor.clear_line + cursor.column(0)
    end

    def move_up(n = 1)
      print cursor.up(n)
    end

    def hide_cursor(&block)
      print cursor.hide
      yield
    ensure
      print cursor.show
    end

  end
end

require_relative "ui/formatting"
require_relative "ui/output"
require_relative "ui/help"
require_relative "ui/errors"
require_relative "ui/nng"
require_relative "ui/confirmations"
require_relative "ui/autocomplete"
require_relative "ui/dashboard"
require_relative "ui/keybindings"
require_relative "ui/progress"
require_relative "ui/diff"
require_relative "ui/spinner"
require_relative "ui/table"

module MASTER
  Help = UI::Help
  ErrorSuggestions = UI::ErrorSuggestions
  NNGChecklist = UI::NNGChecklist
  Confirmations = UI::Confirmations
  ConfirmationGate = UI::Confirmations
end
