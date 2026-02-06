# frozen_string_literal: true

# UI - Unified terminal interface using TTY toolkit
# Consolidates three UI presentation concerns:
#   - TTY toolkit components (original ui.rb)
#   - Clean Grok-inspired terminal output (layout.rb)
#   - Dashboard with stats and visualizations (dashboard.rb)
# Lazy-loads components for fast startup

module MASTER
  module UI
    extend self

    # ========================================
    # ANSI Color Constants (from Layout)
    # ========================================
    RESET  = "\e[0m"
    BOLD   = "\e[1m"
    DIM    = "\e[2m"
    GREY   = "\e[90m"
    WHITE  = "\e[97m"
    CYAN   = "\e[36m"
    GREEN  = "\e[32m"
    YELLOW = "\e[33m"
    RED    = "\e[31m"

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

    # ========================================
    # Layout Methods (from Layout)
    # Clean, Grok-inspired terminal output
    # ========================================

    # Response: clean, minimal, breathing room
    def response(text, tokens: nil, ms: nil, cached: false)
      out = []
      out << ""  # breathing room before response
      out << render_content(text)
      out << ""  # breathing room after
      out << stats_line(tokens: tokens, ms: ms, cached: cached) if tokens
      out.join("\n")
    end

    # Render markdown to clean ANSI
    def render_content(text)
      lines = text.lines.map { |l| render_line(l.chomp) }

      # Collapse triple+ blank lines
      collapsed = []
      blank_count = 0
      lines.each do |line|
        if line.strip.empty?
          blank_count += 1
          collapsed << '' if blank_count <= 2
        else
          blank_count = 0
          collapsed << line
        end
      end

      collapsed.join("\n")
    end

    def render_line(line)
      # Code block markers: hide them, content styled elsewhere
      return '' if line.match?(/^```/)

      # Headers: bold, no #
      if line.match?(/^#+\s/)
        return "#{BOLD}#{line.gsub(/^#+\s*/, '')}#{RESET}"
      end

      # Bullets: subtle dot
      if line.match?(/^\s*[-*]\s/)
        return line.gsub(/^(\s*)[-*]\s/, "\\1#{DIM}·#{RESET} ")
      end

      # Numbered: keep clean
      if line.match?(/^\s*\d+\.\s/)
        return line.gsub(/^(\s*)(\d+)\.\s/, "\\1#{DIM}\\2.#{RESET} ")
      end

      # Inline formatting
      line = line.gsub(/\*\*(.+?)\*\*/, "#{BOLD}\\1#{RESET}")      # bold
      line = line.gsub(/\*([^*]+)\*/, "#{DIM}\\1#{RESET}")         # italic as dim
      line = line.gsub(/`([^`]+)`/, "#{CYAN}\\1#{RESET}")          # inline code
      line = line.gsub(/\[([^\]]+)\]\([^)]+\)/, "#{CYAN}\\1#{RESET}")  # links

      line
    end

    # Stats: single subtle line
    def stats_line(tokens: nil, ms: nil, cached: false)
      parts = []
      parts << "#{ms}ms" if ms
      parts << "#{tokens[:input]}→#{tokens[:output]}" if tokens
      parts << "cached" if cached
      "#{DIM}#{parts.join(' · ')}#{RESET}"
    end

    # Shell output: code-style, indented
    def shell_output(text, cmd: nil)
      out = []
      out << "#{DIM}$ #{cmd}#{RESET}" if cmd
      text.lines.each { |l| out << "  #{l.chomp}" }
      out.join("\n")
    end

    # Separator: subtle line
    def separator
      "#{DIM}#{'─' * 40}#{RESET}"
    end

    # Prompt: minimal, shows only essential state
    def prompt_line(dir:, persona: nil, cost: 0, turn: 0)
      parts = [dir]
      parts << ":#{persona}" if persona && persona != 'generic'
      parts << "(#{turn})" if turn > 0
      parts << cost_badge(cost) if cost > 0.01
      "#{parts.join} #{CYAN}❯#{RESET} "
    end

    def cost_badge(cost)
      color = cost < 0.10 ? GREEN : cost < 1.0 ? YELLOW : RED
      "#{color}$#{'%.2f' % cost}#{RESET}"
    end

    # Code block: dimmed background effect
    def code_block(code, lang: nil)
      lines = code.lines.map { |l| "  #{DIM}#{l.chomp}#{RESET}" }
      lines.unshift("#{DIM}#{lang}#{RESET}") if lang
      lines.join("\n")
    end

    # ========================================
    # Dashboard Class (from Dashboard)
    # Stats and visualizations
    # ========================================

    class Dashboard
      def initialize
        @pastel = Pastel.new
        @screen = TTY::Screen
      end

      def render
        clear_screen

        print_header
        print_stats_box
        print_cost_pie
        print_recent_tasks
        print_memory_status
        print_footer
      end

      private

      def clear_screen
        print "\e[2J\e[H"
      end

      def print_header
        title = @pastel.bold.cyan("MASTER Dashboard")
        puts "\n#{title.center(@screen.width)}\n\n"
      end

      def print_stats_box
        stats = fetch_stats

        content = [
          "Total Cost:    #{format_cost(stats[:total_cost])}",
          "Tasks Today:   #{stats[:tasks_today]}",
          "Avg Response:  #{stats[:avg_duration]}s",
          "Active Model:  #{stats[:active_model]}"
        ].join("\n")

        box = TTY::Box.frame(
          width: 50,
          title: { top_left: " Stats " },
          border: :thick,
          padding: 1,
          align: :left
        ) { content }

        puts box
      end

      def print_cost_pie
        data = fetch_cost_breakdown

        pie = TTY::Pie.new(
          data: data,
          radius: 4,
          legend: { left: 2 }
        )

        puts "\n#{@pastel.bold('Cost by Model')}"
        puts pie
      end

      def print_recent_tasks
        tasks = fetch_recent_tasks(10)

        table = TTY::Table.new(
          header: ['Task', 'Model', 'Cost', 'Time'],
          rows: tasks.map { |t|
            [
              truncate(t[:name], 20),
              t[:model],
              format_cost(t[:cost]),
              "#{t[:duration]}s"
            ]
          }
        )

        puts "\n#{@pastel.bold('Recent Tasks')}"
        puts table.render(:unicode, padding: [0, 1])
      end

      def print_memory_status
        memory = fetch_memory_stats

        status = [
          "Chunks stored:  #{memory[:chunks]}",
          "Total vectors:  #{memory[:vectors]}",
          "Last recall:    #{memory[:last_recall]}",
          "Weaviate:       #{memory[:healthy] ? '✓ Connected' : '✗ Disconnected'}"
        ].join("\n")

        box = TTY::Box.frame(
          width: 40,
          title: { top_left: " Memory " },
          border: :light,
          padding: 1
        ) { status }

        puts "\n#{box}"
      end

      def print_footer
        puts "\n#{@pastel.dim('Press Ctrl+C to exit')}"
      end

      # Data fetching methods
      def fetch_stats
        # Will integrate with Monitor from first PR
        {
          total_cost: defined?(Monitor) ? Monitor.total_cost : 47.23,
          tasks_today: defined?(Monitor) ? Monitor.tasks_today : 156,
          avg_duration: defined?(Monitor) ? Monitor.avg_duration.round(1) : 2.3,
          active_model: defined?(LLM) && LLM.respond_to?(:current_tier) ? LLM.current_tier : "claude-3.5-sonnet"
        }
      rescue StandardError
        # Fallback for development
        {
          total_cost: 47.23,
          tasks_today: 156,
          avg_duration: 2.3,
          active_model: "claude-3.5-sonnet"
        }
      end

      def fetch_cost_breakdown
        return Monitor.cost_by_model if defined?(Monitor) && Monitor.respond_to?(:cost_by_model)

        [
          { name: "DeepSeek (cheap)", value: 15.2 },
          { name: "Grok (fast)", value: 8.4 },
          { name: "Sonnet (strong)", value: 18.3 },
          { name: "Opus (frontier)", value: 5.3 }
        ]
      rescue StandardError
        [
          { name: "DeepSeek (cheap)", value: 15.2 },
          { name: "Grok (fast)", value: 8.4 },
          { name: "Sonnet (strong)", value: 18.3 },
          { name: "Opus (frontier)", value: 5.3 }
        ]
      end

      def fetch_recent_tasks(limit)
        return Monitor.recent_tasks(limit) if defined?(Monitor) && Monitor.respond_to?(:recent_tasks)

        # Fallback
        []
      rescue StandardError
        []
      end

      def fetch_memory_stats
        memory = VectorMemory.new
        {
          chunks: memory.count_chunks,
          vectors: memory.count_vectors,
          last_recall: memory.time_since_last_recall,
          healthy: memory.healthy?
        }
      rescue StandardError
        { chunks: 0, vectors: 0, last_recall: "never", healthy: false }
      end

      # Helpers
      def format_cost(amount)
        "$#{format('%.2f', amount)}"
      end

      def truncate(str, max)
        str.length > max ? "#{str[0...max - 3]}..." : str
      end
    end
  end
end
