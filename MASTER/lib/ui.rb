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
    
    # Bringhurst typographic principles
    module Typography
      extend self
      
      # Maximum line length for readability (Bringhurst recommends 66 chars)
      MAX_LINE_LENGTH = 72
      
      # Convert straight quotes to proper typographic quotes
      def typographic_quotes(text)
        # Use Unicode codepoints for clarity
        left_double = "\u201C"  # "
        right_double = "\u201D" # "
        left_single = "\u2018"  # '
        right_single = "\u2019" # '
        
        text.gsub(/"([^"]+)"/, "#{left_double}\\1#{right_double}")  # "" for quoted text
            .gsub(/(\w)'(\w)/, "\\1#{right_single}\\2")  # ' for contractions
            .gsub(/'([^']+)'/, "#{left_single}\\1#{right_single}")   # '' for single quotes
      end
      
      # Convert double hyphens to em dashes
      def em_dashes(text)
        text.gsub(/--/, '—')
      end
      
      # Convert ellipsis to proper character
      def ellipsis(text)
        text.gsub(/\.\.\./, '…')
      end
      
      # Apply all typographic improvements
      def enhance(text)
        text = typographic_quotes(text)
        text = em_dashes(text)
        text = ellipsis(text)
        text
      end
      
      # Wrap text to max line length with proper indentation
      def wrap(text, width: MAX_LINE_LENGTH, indent: 0)
        lines = []
        current = ''
        indent_str = ' ' * indent
        
        text.split(/\s+/).each do |word|
          if (current + word).length + 1 > width - indent
            lines << indent_str + current.strip unless current.empty?
            current = word + ' '
          else
            current += word + ' '
          end
        end
        
        lines << indent_str + current.strip unless current.empty?
        lines.join("\n")
      end
      
      # Create hierarchical text with proper indentation (no ALL CAPS)
      def hierarchy(text, level: 0)
        indent = '  ' * level
        case level
        when 0
          "#{indent}#{text}"  # No decoration, just text
        when 1
          "\n#{indent}#{text}\n"  # Whitespace as punctuation
        else
          "#{indent}• #{text}"  # Bullet for deeper levels
        end
      end
      
      # Add generous vertical spacing between sections
      def section_break
        "\n\n"
      end
      
      # Format a paragraph with proper typography
      def paragraph(text, width: MAX_LINE_LENGTH)
        enhanced = enhance(text)
        wrapped = wrap(enhanced, width: width)
        wrapped
      end
      
      # Format multiple paragraphs with proper spacing
      def document(*paragraphs, width: MAX_LINE_LENGTH)
        paragraphs.map { |p| paragraph(p, width: width) }.join(section_break)
      end
    end
    
    # Convenience methods for typography
    def typographic(text)
      Typography.enhance(text)
    end
    
    def wrap_text(text, width: 72)
      Typography.wrap(text, width: width)
    end
    
    def format_paragraph(text, width: 72)
      Typography.paragraph(text, width: width)
    end
  end
end
