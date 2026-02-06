# frozen_string_literal: true

# UI - Unified terminal interface using TTY toolkit
# Lazy-loads components for fast startup

module MASTER
  module UI
    extend self

    # Lazy accessors for TTY components
    def prompt
      @prompt ||= begin
        require 'tty-prompt'
        TTY::Prompt.new(symbols: { marker: '›' }, active_color: :cyan)
      end
    end

    def spinner(message = nil, format: :braille)
      require 'tty-spinner'
      TTY::Spinner.new("[:spinner] #{message}", format: format)
    end

    def multi_spinner
      require 'tty-spinner'
      TTY::Spinner::Multi.new("[:spinner] Processing", format: :braille)
    end

    def table(data, header: nil)
      require 'tty-table'
      opts = header ? { header: header } : {}
      TTY::Table.new(opts) { |t| data.each { |row| t << row } }
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
    end

    def markdown(text, width: nil)
      require 'tty-markdown'
      TTY::Markdown.parse(text, width: width || screen_width)
    end

    def progress(total, format: :bar)
      require 'tty-progressbar'
      TTY::ProgressBar.new(
        "[:bar] :percent :eta",
        total: total,
        bar_format: format == :block ? :block : :classic
      )
    end

    def cursor
      @cursor ||= begin
        require 'tty-cursor'
        TTY::Cursor
      end
    end

    def reader
      @reader ||= begin
        require 'tty-reader'
        TTY::Reader.new
      end
    end

    def tree(data)
      require 'tty-tree'
      TTY::Tree.new(data)
    end

    def pie(data)
      require 'tty-pie'
      TTY::Pie.new(data: data, radius: 5)
    end

    def pager
      @pager ||= begin
        require 'tty-pager'
        TTY::Pager.new
      end
    end

    def link(text, url)
      require 'tty-link'
      TTY::Link.link_to(text, url)
    end

    def font(text, font_name = :doom)
      require 'tty-font'
      TTY::Font.new(font_name).write(text)
    end

    def edit(path_or_text)
      require 'tty-editor'
      TTY::Editor.open(path_or_text)
    end

    def command(*cmd, **opts)
      require 'tty-command'
      TTY::Command.new(printer: :quiet).run(*cmd, **opts)
    end

    def screen_width
      @screen_width ||= begin
        require 'tty-screen'
        TTY::Screen.width
      rescue
        80
      end
    end

    def screen_height
      @screen_height ||= begin
        require 'tty-screen'
        TTY::Screen.height
      rescue
        24
      end
    end

    def platform
      @platform ||= begin
        require 'tty-platform'
        TTY::Platform.new
      end
    end

    def which(cmd)
      require 'tty-which'
      TTY::Which.which(cmd)
    end

    def pastel
      @pastel ||= begin
        require 'pastel'
        Pastel.new
      end
    end

    # High-level convenience methods

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
    rescue => e
      s.error
      raise
    end

    def select(question, choices)
      prompt.select(question, choices, cycle: true)
    end

    def multi_select(question, choices)
      prompt.multi_select(question, choices, cycle: true)
    end

    def confirm(question, default: true)
      prompt.yes?(question, default: default)
    end

    def ask(question, default: nil)
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

    # Render LLM response with markdown
    def render_response(text)
      # Try markdown rendering, fallback to plain
      markdown(text)
    rescue => e
      text
    end

    # Display token usage as mini pie chart
    def token_chart(prompt_tokens:, completion_tokens:, cached: 0)
      total = prompt_tokens + completion_tokens
      data = [
        { name: 'prompt', value: prompt_tokens, color: :blue },
        { name: 'completion', value: completion_tokens, color: :green }
      ]
      data << { name: 'cached', value: cached, color: :cyan } if cached > 0
      
      puts pie(data).render
      puts dim("Total: #{total} tokens")
    end

    # Show directory tree
    def show_tree(path, depth: 3)
      require 'tty-tree'
      tree = TTY::Tree.new(path, level: depth)
      puts tree.render
    end
  end
end
