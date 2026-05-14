# frozen_string_literal: true

require_relative "cli/signals"

require "open3"
require "tty-reader"
require "tty-prompt"
require "fileutils"

module Master
  module Now
  class CLI
    IDLE_SLEEP_DEFAULT = 60
    REPLAY_TURNS       = 5
    DMESG_BUFFER       = 80

    SEVERITY_ICON = {
      error: "!!",
      warning: "!",
      style: ".",
      critical: "!!"
    }.freeze

    SLASH_COMMANDS = %w[/exit /undo /redo /history /why /focus /last /cmd /dmesg /chips /propose /principles /restart].freeze

    attr_reader :container

    def initialize(container:)
      @container = container
      assign_container_refs!(container)
      @reader          = TTY::Reader.new(track_history: true)
      @running         = false
      @interrupt_at    = Time.now
      @last_ok         = true
      @violations      = 0
      @prev_violations = 0
      @bg_thread       = nil
      @seen_violations = {}
      @user_active     = false
      @focus_mode      = false
      @show_chips      = false
      @last_input      = nil
      @last_cost       = 0.0
      @dmesg_sub       = nil
      set_visitor_mode_if_unauthenticated
    end

    def run(initial_message = nil)
      setup_signals
      @session.load! if @session.exists?
      start_background_loop
      first_boot_bar
      puts @renderer.splash(@agent.model)
      puts @renderer.session_line(@session.name) if @session.name
      print_repo_tree unless booted_before?
      replay_recent_turns if @session.messages.any?
      run_input(initial_message) if initial_message
      @running = true
      repl_loop
    end

    def pipe(input)
      stripped = input.strip
      return if stripped.empty?
      run_input(stripped)
    end

    def process(input)
      run_input(input)
    end

    def run_input(input)
      return if input.strip.empty?

      @user_active = true
      @last_input  = input
      state    = { streamed: false, thinking_shown: true }
      accumulated = +""
      on_chunk = stream_chunk_handler(accumulated, state)

      print_thinking_indicator
      @pipeline_thread = Thread.new do
        Thread.current.report_on_exception = false
        @pipeline.call(Result.ok(user_message: input, on_chunk: on_chunk))
      end
      result = begin
        @pipeline_thread.value
      rescue StandardError
        Result.err("aborted", category: :abort)
      end
      display_result(result, accumulated, state[:streamed])
    ensure
      @pipeline_thread = nil
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
        end
        print text
        $stdout.flush
        state[:streamed] = true
      end
    end

    private

    def set_visitor_mode_if_unauthenticated
      web_token = @config&.dig("web_token")
      Thread.current[:master_visitor] = true if web_token.nil? || web_token.empty?
    end

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
        unless @focus_mode
          status = @renderer.status_row(uptime: @renderer.uptime, turns: @session.messages.size, violations: @violations)
          puts status if status
          sugg = suggested_next_prompt
          puts @renderer.render("  ↳ #{sugg}", mode: :dim) if sugg
          tokens = @session.token_est
          prompt_lines = @renderer.prompt_line(
            @agent.model, @session.phase,
            last_ok: @last_ok, violations: @violations, tokens: tokens, cost: @session.cost
          )
          puts prompt_lines.first
          print prompt_lines.last
        else
          print @renderer.render("master$ ", mode: :dim)
        end
        line = safe_read_line
        break if line.nil?
        handle_repl_line(line)
      end
      @bg_thread&.kill
      @session.save!
    end

    def suggested_next_prompt
      top = proposer.top
      return nil unless top
      @last_suggestion = top[:action]
      "#{top[:action]}  (#{top[:reason]})"
    end

    def accept_top_suggestion
      return unless @last_suggestion
      puts @renderer.render("↳ #{@last_suggestion}", mode: :dim)
      handle_repl_line(@last_suggestion)
    end

    def proposer
      @proposer ||= Master::Propose.new(container: @container)
      @proposer.violations = @violations
      @proposer
    end

    def handle_repl_line(line)
      stripped = line.strip
      return accept_top_suggestion if stripped.empty?
      case stripped
      when "/exit"    then exit_cli
      when "/undo"    then run_undo
      when "/redo"    then run_redo
      when "/history" then run_history
      when "/why"     then run_why
      when "/focus"   then toggle_focus
      when "/last"    then run_last
      when "/cmd"     then run_cmd
      when "/dmesg"   then toggle_dmesg
      when "/chips"   then toggle_chips
      when "/propose"    then run_propose
      when "/principles" then run_principles
      when "/restart"    then run_restart
      when "<<"       then run_input(read_multiline)
      else                 run_input(line)
      end
    end

    def run_restart
      @session.save!
      puts @renderer.render("restart: exec'ing fresh master in place", mode: :dim)
      $stdout.flush
      Kernel.exec(RbConfig.ruby, $PROGRAM_NAME, *ARGV)
    end

    def run_undo
      res = @undo.undo!
      if res.respond_to?(:ok?) && res.ok?
        puts @renderer.render("undo: #{Array(res.value!).join(", ")}", mode: :success)
      else
        puts @renderer.render(res.message, mode: :warning)
      end
    end

    def run_redo
      res = @undo.redo!
      if res.respond_to?(:ok?) && res.ok?
        puts @renderer.render("redo: #{Array(res.value!).join(", ")}", mode: :success)
      else
        puts @renderer.render(res.message, mode: :warning)
      end
    end

    def run_history
      lines = @undo.history(limit: 10)
      if lines.empty?
        puts @renderer.render("no undo history", mode: :dim)
      else
        lines.each { |l| puts @renderer.render(l, mode: :dim) }
      end
    end

    def run_why
      router = Master::Routing::ModelRouter.new(config: @config, root: Master::ROOT)
      task = @session.phase == :implement ? :implement : :exploration
      tier = router.current_tier(task_type: task)
      rows = router.score_breakdown(task_type: task).first(5)
      puts @renderer.render("router: phase=#{@session.phase} task=#{task} tier=#{tier}", mode: :dim)
      rows.each_with_index do |r, i|
        line = format("  %d. %-40s q=%.2f s=%.2f c=%.2f → %.3f",
                      i + 1, r[:id].to_s[0, 40], r[:q], r[:s], r[:c], r[:total])
        puts @renderer.render(line, mode: :dim)
      end
    end

    def toggle_focus
      @focus_mode = !@focus_mode
      puts @renderer.render("focus: #{@focus_mode ? "on" : "off"}", mode: :dim)
    end

    def run_last
      if @last_input
        puts @renderer.render("rerun: #{@last_input[0, 60]}", mode: :dim)
        run_input(@last_input)
      else
        puts @renderer.render("no prior input", mode: :dim)
      end
    end

    def run_cmd
      SLASH_COMMANDS.each { |c| puts @renderer.render("  #{c}", mode: :dim) }
    end

    def toggle_dmesg
      if @dmesg_sub
        @dmesg_sub.call
        @dmesg_sub = nil
        puts @renderer.render("dmesg: off", mode: :dim)
      else
        @dmesg_sub = @bus&.subscribe("*") do |payload|
          ts   = payload[:ts] || 0
          line = "  [#{ts.to_s.rjust(7)}] #{payload[:event]}"
          $stdout.puts @renderer.render(line, mode: :dim) rescue nil
        end
        puts @renderer.render("dmesg: on (events stream below)", mode: :dim)
      end
    end

    def toggle_chips
      @show_chips = !@show_chips
      puts @renderer.render("chips: #{@show_chips ? "on" : "off"}", mode: :dim)
    end

    def run_principles
      c = Master::Ground::Constitution.new
      lines = c.list
      if lines.empty?
        puts @renderer.render("no principles loaded (data/principles/*.md)", mode: :dim)
      else
        puts @renderer.render("constitution: #{lines.size} principle(s)", mode: :dim)
        lines.each { |l| puts @renderer.render("  #{l}", mode: :dim) }
      end
    end

    def run_propose
      rows = proposer.call
      if rows.empty?
        puts @renderer.render("propose: nothing pressing — try /history or scan a dir", mode: :dim)
        return
      end
      puts @renderer.render("propose0: top #{rows.size} suggestion(s)", mode: :dim)
      rows.each_with_index do |r, i|
        line = format("  %d. %-22s %s", i + 1, r[:action], r[:reason])
        puts @renderer.render(line, mode: :dim)
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

    def replay_recent_turns
      tail = @session.messages.last(REPLAY_TURNS * 2)
      return if tail.empty?
      puts @renderer.render("resume0: replaying last #{tail.size} messages", mode: :dim)
      tail.each do |msg|
        tag     = msg[:role] == :user ? "you" : "master"
        snippet = msg[:content].to_s.lines.first.to_s.strip[0, 100]
        puts @renderer.render("  #{tag}: #{snippet}", mode: :dim)
      end
      puts
    end

    def start_background_loop
      cfg           = Master::Loop::AutoLoop.load_cfg
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
      return unless result.respond_to?(:ok?) && result.ok?

      prev = @prev_violations
      @violations      = count_violations(result.value!)
      @prev_violations = @violations
      return if @violations.zero? && prev.zero?

      delta = @violations - prev
      arrow = delta.zero? ? "·" : (delta.positive? ? "↑" : "↓")
      puts
      puts @renderer.render("boot scan: #{prev} #{arrow} #{@violations} violation(s)", mode: :dim)
      puts
    rescue StandardError => e
      @bus&.publish("cli:warn", error: e.message)
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
        file_result.respond_to?(:ok?) && file_result.ok? ? file_result.value!.size : 0
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

    SPIN_FRAMES   = ["\u00B7", "\u2219", "\u2022", "\u25CF"].freeze
    SPIN_INTERVAL = 0.25
    DMESG_IGNORE  = %w[bus:subscribe bus:unsubscribe ring:write].freeze
    VERDICT_GLYPH = {
      ok: "\u2713", fail: "\u00D7", warn: "!", info: "\u00B7"
    }.freeze

    def print_thinking_indicator
      return unless $stdout.isatty

      @think_mutex = Mutex.new
      @think_t0    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @think_stage = "intake"
      @think_sub   = @bus&.subscribe("*") do |payload|
        update_think_stage(payload)
        emit_dmesg_line(payload)
      end

      @spin_thread = Thread.new do
        i = 0
        loop do
          @think_mutex.synchronize do
            print "\r\e[K#{@renderer.render("#{SPIN_FRAMES[i % SPIN_FRAMES.size]} #{@think_stage}", mode: :dim)}"
            $stdout.flush
          end
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
      @think_sub&.call
      @think_sub = nil
    end

    def update_think_stage(payload)
      ev = payload[:event].to_s
      return unless ev.start_with?("stage:")
      stage = payload[:stage] || ev.sub("stage:", "")
      @think_stage = stage.to_s
    end

    def glyph_for_event(ev)
      case ev
      when /:(done|ok|success|rendered|synthesis)\b/ then VERDICT_GLYPH[:ok]
      when /:(error|fail|timeout|veto)\b/            then VERDICT_GLYPH[:fail]
      when /:(warn|warning|escalat)\b/               then VERDICT_GLYPH[:warn]
      else                                                VERDICT_GLYPH[:info]
      end
    end

    MUTATING_TOOLS = %w[WriteFile Edit StrReplace BatchReplace AstEdit FilePatch].freeze

    def emit_dmesg_line(payload)
      ev = payload[:event].to_s
      return if ev.empty? || DMESG_IGNORE.include?(ev)
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - (@think_t0 || 0)) * 1000).to_i
      kv = payload.reject { |k, _| %i[event ts topic].include?(k) }
                  .map { |k, v| "#{k}=#{v.to_s[0, 60]}" }.join(" ")
      diff = ev == "tool:after" && MUTATING_TOOLS.include?(payload[:tool].to_s) ? diff_stat(payload[:path]) : nil
      tail = diff ? " #{diff}" : ""
      line = "  %s [%7d] %s%s%s" % [glyph_for_event(ev), ms, ev, kv.empty? ? "" : " #{kv}", tail]
      @think_mutex&.synchronize do
        print "\r\e[K"
        $stdout.puts @renderer.render(line, mode: :dim)
        $stdout.flush
      end
    rescue StandardError
      nil
    end

    def diff_stat(path)
      return nil unless path && !path.empty?
      out, _ = Open3.capture2e("git", "-C", @root, "diff", "--numstat", "--", path)
      m = out.lines.first&.match(/^(\d+)\s+(\d+)/)
      m ? "+#{m[1]}/-#{m[2]}" : nil
    rescue StandardError
      nil
    end

    INIT_FRAMES   = 20
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
          error_text = format_error_message(err)
          puts @renderer.render(error_text, mode: :error)
          puts
        end
      end
    end

    def format_error_message(err)
      msg = err.message.to_s
      return msg if msg.bytesize <= 200

      msg[0, 197] + "…"
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
      print_cost_tooltip
      print_chips if @show_chips
    end

    def print_cost_tooltip
      now_cost = @session.cost.to_f
      delta    = now_cost - @last_cost
      @last_cost = now_cost
      tokens = @session.token_est
      cents  = (delta * 100).round(2)
      return if cents.zero? && tokens.zero?
      line = "cost: +¢#{format('%.2f', cents)} · #{tokens} tok · #{short_model(@agent.model)}"
      puts @renderer.render(line, mode: :dim)
    end

    def print_chips
      chips = next_action_chips
      return if chips.empty?
      puts @renderer.render("  next: #{chips.join("  ")}", mode: :dim)
    end

    def next_action_chips
      base = ["[/undo]", "[/why]", "[/last]"]
      base.unshift("[/polish #{@violations}v]") if @violations.positive?
      base
    end

    def short_model(model)
      model.to_s.sub(/\Aclaude-cli:/, "").sub(/\Aweb-chat:/, "").split("/").last.to_s.sub(/:free$/, "")
    end
  end
  end
end
