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

    def color_enabled?
      return false if ENV["NO_COLOR"]
      return false if ENV["TERM"] == "dumb"
      true
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

    # --- Special rendering methods ---

    def render_response(text)
      # Try markdown rendering, fallback to plain
      markdown(text)
    rescue => e
      text
    end

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

    def show_tree(path, depth: 3)
      require 'tty-tree'
      tree_obj = TTY::Tree.new(path, level: depth)
      puts tree_obj.render
    rescue LoadError
      # Simple fallback
      Dir.glob(File.join(path, '*')).each do |f|
        puts "  #{File.basename(f)}"
      end
    end

    # --- Colorization for dmesg and system output ---
    
    def dmesg(subsystem, message, level: :info)
      elapsed = (Time.now - MASTER_BOOT_TIME).round(6)
      prefix = format("[%12.6f]", elapsed)
      line = "#{prefix} #{subsystem}: #{message}"
      case level
      when :error, :warn then $stderr.puts line
      else puts line
      end
    end
    
    def colorize(text)
      return text unless color_enabled?
      text
        .gsub(/^(\w+) at (\w+):/) { "#{pastel.blue($1)} at #{pastel.cyan($2)}:" }
        .gsub(/^(MASTER .+)$/) { pastel.bold.magenta($1) }
        .gsub(/(\d+) (axioms|personas|stages)/) { "#{pastel.bright_magenta($1)} #{$2}" }
        .gsub(/(\$[\d.]+)/) { pastel.bright_cyan($1) }
        .gsub(/(armed|available)/) { pastel.green($1) }
        .gsub(/(unavailable|error)/) { pastel.red($1) }
        .gsub(/(\d+ms)$/) { pastel.bright_black($1) }
    end
  end

  # === Autocomplete - Tab completion for REPL ===
  # Merged from autocomplete.rb
  module Autocomplete
    extend self

    COMMANDS = %w[help status budget clear history refactor chamber evolve speak exit quit ask scan].freeze

    def complete(partial, context: nil)
      completions = []

      # Command completion
      if partial.match?(/^\w*$/)
        completions += COMMANDS.select { |c| c.start_with?(partial) }
      end

      # File path completion
      if partial.include?('/') || partial.include?('\\') || partial.end_with?('.rb')
        completions += complete_path(partial)
      end

      # After known commands, suggest relevant completions
      if context
        case context
        when 'refactor', 'chamber'
          completions += complete_path(partial).select { |p| p.end_with?('.rb') }
        when 'speak', 'say'
          # No completion for freeform text
        end
      end

      completions.uniq
    end

    def complete_path(partial)
      dir = File.dirname(partial)
      dir = '.' if dir == partial
      base = File.basename(partial)

      return [] unless Dir.exist?(dir)

      Dir.entries(dir)
         .reject { |e| e.start_with?('.') }
         .select { |e| e.start_with?(base) }
         .map { |e| File.join(dir, e) }
    rescue StandardError
      []
    end

    def setup_readline
      return unless defined?(Readline)

      Readline.completion_proc = proc do |input|
        complete(input)
      end
      Readline.completion_append_character = ' '
    end

    def setup_tty(reader)
      return unless reader.respond_to?(:on)

      reader.on(:keypress) do |event|
        if event.key.name == :tab
          word = event.line.text.split.last || ''
          matches = complete(word)
          if matches.size == 1
            # Replace word with completion
            event.line.replace(event.line.text.sub(/#{Regexp.escape(word)}$/, matches.first))
          elsif matches.size > 1
            puts "\n#{matches.join('  ')}"
          end
        end
      end
    end
  end

  # === Dashboard - Terminal status display ===
  # Merged from dashboard.rb
  class Dashboard
    def initialize
      @ui = UI
    end

    def render
      clear
      header
      stats_box
      budget_box
      recent_activity
      footer
    end

    private

    def clear
      print "\e[2J\e[H"
    end

    def header
      puts @ui.bold("\n  MASTER Dashboard v#{VERSION}\n")
      puts "  #{'-' * 40}\n"
    end

    def stats_box
      stats = fetch_stats

      puts "  #{@ui.bold('System Status')}"
      puts "    Model Tier:    #{stats[:tier]}"
      puts "    Budget:        #{UI.currency(stats[:remaining])} / #{UI.currency(stats[:limit])}"
      puts "    Circuit:       #{stats[:circuits_ok]} ok, #{stats[:circuits_tripped]} tripped"
      puts "    Axioms:        #{stats[:axioms]}"
      puts "    Council:       #{stats[:council]} personas"
      puts
    end

    def budget_box
      spent = LLM::SPENDING_CAP - LLM.budget_remaining
      pct = (spent / LLM::SPENDING_CAP * 100).round(1)

      bar_width = 30
      filled = (pct / 100.0 * bar_width).round
      bar = "[#{'█' * filled}#{'░' * (bar_width - filled)}]"

      puts "  #{@ui.bold('Budget Usage')}"
      puts "    #{bar} #{pct}%"
      puts
    end

    def recent_activity
      puts "  #{@ui.bold('Recent Activity')}"

      costs = DB.recent_costs(limit: 5)

      if costs.empty?
        puts "    (no activity yet)"
      else
        costs.each do |row|
          model = row[:model].split("/").last
          cost = row[:cost]
          created = row[:created_at]
          puts "    #{created[11, 5]} | #{model.ljust(15)} | #{UI.currency_precise(cost)}"
        end
      end
      puts
    end

    def footer
      puts "  #{@ui.dim('Press any key to return...')}"
    end

    def fetch_stats
      {
        tier: LLM.tier,
        remaining: LLM.budget_remaining,
        limit: LLM::SPENDING_CAP,
        circuits_ok: LLM.models.count { |m| LLM.circuit_closed?(m[:id]) },
        circuits_tripped: LLM.models.count { |m| !LLM.circuit_closed?(m[:id]) },
        axioms: DB.axioms.size,
        council: DB.council.size,
      }
    rescue StandardError
      { tier: :unknown, remaining: 0, limit: 10, circuits_ok: 0, circuits_tripped: 0, axioms: 0, council: 0 }
    end
  end

  # === Keybindings - Keyboard shortcuts for REPL ===
  # Merged from keybindings.rb
  module Keybindings
    BINDINGS = {
      ctrl_c:    { action: :interrupt,   desc: "Cancel current operation" },
      ctrl_d:    { action: :exit,        desc: "Exit MASTER" },
      ctrl_l:    { action: :clear,       desc: "Clear screen" },
      ctrl_r:    { action: :history,     desc: "Search history" },
      ctrl_z:    { action: :undo,        desc: "Undo last operation" },
      ctrl_y:    { action: :redo,        desc: "Redo undone operation" },
      tab:       { action: :autocomplete, desc: "Tab completion" },
      up:        { action: :history_up,  desc: "Previous command" },
      down:      { action: :history_down, desc: "Next command" },
      f1:        { action: :help,        desc: "Show help" },
      f2:        { action: :status,      desc: "Show status" }
    }.freeze

    extend self

    def setup(reader)
      return unless reader.respond_to?(:on)

      reader.on(:keyctrl_l) { print "\e[2J\e[H" }
      reader.on(:keyctrl_z) { Undo.undo if defined?(Undo) }
      reader.on(:keyctrl_y) { Undo.redo if defined?(Undo) }
    end

    def help_text
      lines = ["Keyboard Shortcuts:", ""]
      BINDINGS.each do |key, info|
        key_name = key.to_s.gsub('_', '+').gsub('ctrl', 'Ctrl')
        lines << "  #{key_name.ljust(12)} #{info[:desc]}"
      end
      lines.join("\n")
    end
  end

  # === Progress - Show progress during LLM calls (NN/g: visibility of system status) ===
  # Merged from progress.rb
  module Progress
    extend self

    SPINNERS = {
      dots:    %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏],
      line:    %w[- \\ | /],
      blocks:  %w[▏ ▎ ▍ ▌ ▋ ▊ ▉ █],
      arrows:  %w[← ↖ ↑ ↗ → ↘ ↓ ↙],
      circuit: %w[◯ ◔ ◑ ◕ ●]
    }.freeze

    class Spinner
      def initialize(message = "Processing...", style: :dots)
        @message = message
        @frames = SPINNERS[style] || SPINNERS[:dots]
        @index = 0
        @running = false
        @thread = nil
      end

      def start
        @running = true
        @thread = Thread.new do
          while @running
            print "\r  #{@frames[@index % @frames.size]} #{@message}"
            @index += 1
            sleep 0.1
          end
        end
        self
      end

      def update(message)
        @message = message
      end

      def stop(final_message = nil)
        @running = false
        @thread&.join
        print "\r#{' ' * 60}\r"
        puts "  ✓ #{final_message}" if final_message
      end

      def success(message)
        stop("#{message}")
      end

      def error(message)
        @running = false
        @thread&.join
        print "\r#{' ' * 60}\r"
        puts "  ✗ #{message}"
      end
    end

    class ProgressBar
      def initialize(total:, message: "Progress")
        @total = total
        @current = 0
        @message = message
        @start_time = Time.now
      end

      def advance(by = 1)
        @current += by
        render
      end

      def set(value)
        @current = value
        render
      end

      def finish
        @current = @total
        render
        puts
      end

      private

      def render
        pct = (@current.to_f / @total * 100).round(1)
        bar_width = 30
        filled = (pct / 100.0 * bar_width).round
        bar = "[#{'█' * filled}#{'░' * (bar_width - filled)}]"

        elapsed = Time.now - @start_time
        eta = @current > 0 ? (elapsed / @current * (@total - @current)).round : 0

        print "\r  #{@message}: #{bar} #{pct}% (#{@current}/#{@total}) ETA: #{eta}s"
      end
    end

    def spinner(message = "Processing...", style: :dots, &block)
      s = Spinner.new(message, style: style)
      s.start

      result = yield
      s.success("Done")
      result
    rescue => e
      s.error(e.message)
      raise
    end

    def progress_bar(total:, message: "Progress", &block)
      bar = ProgressBar.new(total: total, message: message)
      yield bar
      bar.finish
    end

    def thinking(duration = nil)
      frames = %w[thinking. thinking.. thinking...]
      spinner = Spinner.new(frames.first, style: :circuit)
      spinner.start

      if block_given?
        result = yield
        spinner.success("Complete")
        result
      else
        # Auto-stop after duration if given
        if duration
          sleep duration
          spinner.stop
        end
        spinner
      end
    end
  end

  # === DiffView - Generate unified diffs for preview ===
  # Merged from diff_view.rb
  module DiffView
    extend self

    # Generate a unified diff between original and modified content
    # Returns a string in unified diff format
    def unified_diff(original, modified, filename: "file", context_lines: 3)
      original_lines = original.lines.map(&:chomp)
      modified_lines = modified.lines.map(&:chomp)

      output = []
      output << "--- a/#{filename}"
      output << "+++ b/#{filename}"

      # Use a simple line-by-line comparison for now
      hunks = compute_hunks(original_lines, modified_lines, context_lines)
      
      hunks.each do |hunk|
        output << hunk[:header]
        output.concat(hunk[:lines])
      end

      output.join("\n") + "\n"
    end

    private

    def compute_hunks(original, modified, context)
      # Find all differences
      changes = []
      max_len = [original.length, modified.length].max
      
      (0...max_len).each do |i|
        orig_line = original[i]
        mod_line = modified[i]
        
        if orig_line == mod_line
          changes << { type: :same, orig: i, mod: i }
        elsif orig_line.nil?
          changes << { type: :add, orig: i, mod: i }
        elsif mod_line.nil?
          changes << { type: :delete, orig: i, mod: i }
        else
          # Line changed
          changes << { type: :change, orig: i, mod: i }
        end
      end

      # Group into hunks
      hunks = []
      i = 0
      
      while i < changes.length
        # Skip unchanged lines that are far from changes
        while i < changes.length && changes[i][:type] == :same
          # Look ahead to find next change
          next_change = find_next_change(changes, i)
          break if next_change && (next_change - i) <= context * 2
          i += 1
        end
        
        next if i >= changes.length
        
        # Start a new hunk
        hunk_start = [i - context, 0].max
        
        # Find end of hunk (include context after last change)
        hunk_end = i
        while hunk_end < changes.length
          if changes[hunk_end][:type] != :same
            # Found a change, continue
            hunk_end += 1
          else
            # Check if there's another change within context
            next_change = find_next_change(changes, hunk_end)
            if next_change && (next_change - hunk_end) <= context * 2
              hunk_end = next_change
            else
              # No more changes nearby, add context and stop
              hunk_end = [hunk_end + context, changes.length].min
              break
            end
          end
        end
        
        # Build this hunk
        orig_start = changes[hunk_start][:orig]
        mod_start = changes[hunk_start][:mod]
        orig_count = 0
        mod_count = 0
        lines = []
        
        (hunk_start...hunk_end).each do |j|
          change = changes[j]
          case change[:type]
          when :same
            lines << " #{original[change[:orig]]}"
            orig_count += 1
            mod_count += 1
          when :delete
            lines << "-#{original[change[:orig]]}" if change[:orig] < original.length
            orig_count += 1
          when :add
            lines << "+#{modified[change[:mod]]}" if change[:mod] < modified.length
            mod_count += 1
          when :change
            lines << "-#{original[change[:orig]]}" if change[:orig] < original.length
            lines << "+#{modified[change[:mod]]}" if change[:mod] < modified.length
            orig_count += 1
            mod_count += 1
          end
        end
        
        unless lines.empty?
          hunks << {
            header: "@@ -#{orig_start + 1},#{orig_count} +#{mod_start + 1},#{mod_count} @@",
            lines: lines
          }
        end
        
        i = hunk_end
      end

      hunks
    end

    def find_next_change(changes, start)
      (start...changes.length).each do |i|
        return i if changes[i][:type] != :same
      end
      nil
    end
  end
end

# Load ui submodules for backwards compatibility
require_relative "ui/spinner" if File.exist?(File.join(__dir__, "ui/spinner.rb"))
require_relative "ui/table" if File.exist?(File.join(__dir__, "ui/table.rb"))

