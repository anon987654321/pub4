# frozen_string_literal: true

require_relative "cli/signals"

require "open3"
require "tty-reader"
require "tty-prompt"
require "fileutils"

module Master
  class CLI
    IDLE_SLEEP_DEFAULT = 60

    SEVERITY_ICON = {
      error: "!!",
      warning: "!",
      style: ".",
      critical: "!!"
    }.freeze

    attr_reader :container

    def initialize(container:)
      @container = container
      assign_container_refs!(container)
      @reader          = TTY::Reader.new(track_history: true)
      @running         = false
      @interrupt_at    = Time.now
      @last_ok         = true
      @violations      = 0
      @bg_thread       = nil
      @seen_violations = {}
      @user_active     = false
      @last_scan_at    = nil
    end

    def run(initial_message = nil)
      setup_signals
      @session.load! if @session.exists?
      start_background_loop
      first_boot_bar
      puts @renderer.splash(@agent.model)
      puts @renderer.session_line(@session.name) if @session.name
      print_repo_tree unless booted_before?
      process(initial_message) if initial_message
      @running = true
      repl_loop
    end

    def pipe(input)
      stripped = input.strip
      return if stripped.empty?

      run_input(stripped)
    end

    def run_input(input)
      return if input.strip.empty?

      @user_active = true
      state    = { streamed: false, thinking_shown: true }
      accumulated = +""
      on_chunk = stream_chunk_handler(accumulated, state)

      print_thinking_indicator
      result = @pipeline.call(Result.ok(user_message: input, on_chunk: on_chunk))
      display_result(result, accumulated, state[:streamed])
    ensure
      stop_thinking_indicator
      @user_active = false
    end

    def stream_chunk_handler(accumulated, state)
      chunk_accumulator(accumulated) do |text|
        if state[:thinking_shown] && $stdout.isatty
          stop_thinking_indicator
          print "\r\e[K"
          state[:thinking_shown] = false
        end
        unless state[:streamed]
          puts @renderer.speaker_tag
          puts
        end
        print text
        $stdout.flush
        state[:streamed] = true
      end
    end

    private

    def assign_container_refs!(deps)
      @session     = deps[:session]
      @agent       = deps[:agent]
      @renderer    = deps[:renderer]
      @logging     = deps[:logging]
      @undo        = deps[:undo]
      @config      = deps[:config]
      @pipeline    = deps[:pipeline]
      @scanner     = deps[:scanner]
      @autoloop    = deps[:autoloop]
      @root        = deps[:root] || Dir.pwd
      @diff_stager = deps[:diff_stager]
      @bus         = deps[:bus]
    end

    def repl_loop
      while @running
        print_dashboard
        tokens = @session.token_est
        print @renderer.prompt_line(
          @agent.model, @session.phase,
          last_ok: @last_ok, violations: @violations, tokens: tokens, cost: @session.cost
        )
        puts prompt_lines.first
        print prompt_lines.last
        line = safe_read_line
        break if line.nil?
        handle_repl_line(line)
      end
      @bg_thread&.kill
      @session.save!
    end

    def handle_repl_line(line)
      stripped = line.strip
      return if stripped.empty?
      case stripped
      when "/exit" then exit_cli
      when "<<"    then run_input(read_multiline)
      else              run_input(line)
      end
    end

    def safe_read_line
      @reader.read_line("", echo: true).chomp
    rescue StandardError
      nil
    end

    def exit_cli
      @session.save!
      line = @renderer.closing
      puts line if line
      @running = false
    end

    def read_multiline
      lines = []
      puts @renderer.render("-- enter lines, blank line to send --", mode: :dim)
      loop do
        print "  "
        inner = safe_read_line
        break if inner.nil? || inner.strip.empty?
        lines << inner
      end
      lines.join("\n")
    end

    def start_background_loop
      cfg           = AutoLoop.load_cfg
      return unless cfg.fetch("background", true)
      idle_interval = cfg.fetch("idle_sleep", IDLE_SLEEP_DEFAULT)
      @bg_thread = Thread.new do
        boot_scan
        loop do
          sleep idle_interval
          background_cycle unless @user_active
        end
      rescue StandardError => e
        @bus&.publish("cli:bg_error", error: e.message)
      end
    end

    def boot_scan
      lib_dir = File.join(@root, "lib")
      changed = changed_lib_files(lib_dir)
      result  = changed.any? ? scan_files(changed) : @scanner.scan_dir(lib_dir, depth: :standard)
      return unless result.is_a?(Master::Result::Ok)

      @violations = count_violations(result.value!)
      @last_scan_at = Time.now
      return if @violations.zero?

      puts
      puts @renderer.render("boot scan: #{@violations} violation(s)", mode: :dim)
      puts
    rescue StandardError => e
      @bus&.publish("cli:warn", error: e.message)
    end

    def print_dashboard
      used = @session.cost.to_f
      max_budget = @config["budget_max"] || 10.0
      mood = @last_ok ? "focused" : "recovering"
      last_scan = @last_scan_at ? "#{((Time.now - @last_scan_at).round)}s ago" : "never"
      files = Master::CommandRegistry.tree_lines(@root).size
      puts @renderer.command_summary(
        model: @agent.model,
        budget_used: used,
        budget_max: max_budget,
        violations: @violations,
        phase: @session.phase,
        mood: mood,
        uptime: @renderer.uptime,
        last_scan: last_scan,
        file_count: files
      )
    rescue StandardError
      nil
    end

    def changed_lib_files(lib_dir)
      out, = Open3.capture2e("git", "-C", @root, "diff", "--name-only", "HEAD")
      return [] if out.strip.empty?
      out.lines
         .map { |l| File.join(@root, l.strip) }
         .select { |p| p.start_with?(lib_dir) && p.end_with?(".rb") && File.exist?(p) }
    rescue StandardError
      []
    end

    def scan_files(paths)
      Result.ok(paths.map { |p| [p, @scanner.scan(p, depth: :standard)] })
    end

    def count_violations(pairs)
      pairs.sum do |_file, file_result|
        file_result.is_a?(Master::Result::Ok) ? file_result.value!.size : 0
      end
    end

    def background_cycle
      return unless @autoloop

      @autoloop.run(max_cycles: 1) do |_cycle, violations|
        n = violations.size
        next if n.zero?
        @violations = n
        top = violations.first(3).map { |v| "#{File.basename(v[:file])}:#{v[:rule]}" }.join(" ")
        $stdout.puts "\nautoloop: #{n} violation(s) #{top}"
        $stdout.flush
      end
    rescue StandardError => e
      @bus&.publish("autoloop:bg_error", error: e.message)
    end

    def chunk_accumulator(buffer)
      lambda do |chunk|
        text = chunk.respond_to?(:content) ? chunk.content.to_s : chunk.to_s
        next if text.empty?

        yield text
        buffer << text
      end
    end

    SPIN_FRAMES = ["\u00B7", "\u2219", "\u2022", "\u25CF"].freeze
    SPIN_INTERVAL = 0.25

    def print_thinking_indicator
      return unless $stdout.isatty

      @spin_thread = Thread.new do
        i = 0
        loop do
          print "\r\e[K#{@renderer.render("#{SPIN_FRAMES[i % SPIN_FRAMES.size]} thinking", mode: :dim)}"
          $stdout.flush
          sleep SPIN_INTERVAL
          i += 1
        end
      rescue StandardError => _e
        nil
      end
    end

    def stop_thinking_indicator
      @spin_thread&.kill
      @spin_thread = nil
    end

    INIT_FRAMES = 20
    INIT_FRAME_MS = 0.04

    def print_repo_tree
      lines = Master::CommandRegistry.tree_lines(@root)
      return if lines.empty?
      puts @renderer.render("tree0: #{File.basename(@root)} (#{lines.size} entries)", mode: :dim)
      lines.each { |l| puts @renderer.render(l, mode: :dim) }
      puts
    rescue StandardError
      nil
    end

    def booted_before?
      flag = File.join(@root, ".master", "booted_once")
      File.exist?(flag)
    rescue StandardError
      false
    end

    def first_boot_bar
      return unless $stdout.isatty
      flag = File.join(@root, ".master", "booted_once")
      return if File.exist?(flag)
      INIT_FRAMES.times do |i|
        bar = ("\u25B0" * (i + 1)) + ("\u25B1" * (INIT_FRAMES - i - 1))
        pct = ((i + 1) * 100 / INIT_FRAMES).to_s.rjust(3)
        print "\rinit0: #{bar} #{pct}%"
        $stdout.flush
        sleep INIT_FRAME_MS
      end
      puts
      FileUtils.mkdir_p(File.dirname(flag))
      File.write(flag, Time.now.to_s)
    rescue StandardError
      nil
    end

    def display_result(result, accumulated, streamed)
      case result
      in Master::Result::Ok => ok
        @last_ok = true
        display_ok(ok, accumulated, streamed)
      in Master::Result::Err => err
        @last_ok = false
        if err.category == :shutdown
          exit_cli
        else
          puts
          puts @renderer.render(err.message, mode: :error)
          puts
        end
      end
    end

    def display_ok(ok, _accumulated, streamed)
      if streamed
        puts
        puts
      else
        print "\r\e[K" if $stdout.isatty
        value    = ok.value
        rendered = value.is_a?(Hash) ? value[:rendered] : nil
        text     = rendered || value.to_s
        puts @renderer.speaker_tag
        puts text
        puts
      end
    end
  end
end
