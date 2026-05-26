# frozen_string_literal: true

require_relative "cli/signals"
require_relative "cli/command_ops"
require_relative "cli/thinking_indicator"

require "open3"
require "tty-reader"
require "tty-prompt"
require "fileutils"

module Master
  module Now
  class CLI
    IDLE_SLEEP_DEFAULT = 60
    REPLAY_TURNS = 5
    DMESG_BUFFER = 80

    SEVERITY_ICON = {
      error: "!!",
      warning: "!",
      style: ".",
      critical: "!!"
    }.freeze

    SLASH_COMMANDS = %w[
      /exit /undo /redo /history /why /focus /last /cmd /dmesg /chips /propose /principles /restart
      /ui-critique /sound-critique /rebuild /context /checkpoint /verify
    ].freeze

    attr_reader :container

    def initialize(container:)
      @container = container
      assign_container_refs!(container)
      @reader = TTY::Reader.new(track_history: true)
      @running = false
      @interrupt_at = Time.now
      @last_ok = true
      @violations = 0
      @prev_violations = 0
      @bg_thread = nil
      @seen_violations = {}
      @user_active = false
      @focus_mode = false
      @show_chips = false
      @last_input = nil
      @last_cost = 0.0
      @dmesg_sub = nil
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
      @last_input = input
      state = { streamed: false, thinking_shown: true }
      accumulated = +""
      on_chunk = stream_chunk_handler(accumulated, state)

      print_thinking_indicator
      @pipeline_thread = Thread.new do
        Thread.current.report_on_exception = false
        @pipeline.call(Result.ok(user_message: input, on_chunk: on_chunk))
      end
      result = begin
        @pipeline_thread.value
      rescue StandardError => _e
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
      Fiber[:master_visitor] = true if web_token.nil? || web_token.empty?
    end

    def assign_container_refs!(deps)
      @session = deps[:session]
      @agent = deps[:agent]
      @renderer = deps[:renderer]
      @logging = deps[:logging]
      @undo = deps[:undo]
      @config = deps[:config]
      @pipeline = deps[:pipeline]
      @scanner = deps[:scanner]
      @root = deps.fetch(:root, Dir.pwd)
      @diff_stager = deps[:diff_stager]
      @bus = deps[:bus]
    end

    def repl_loop
      while @running
        unless @focus_mode
          status = @renderer.status_row(
            uptime: @renderer.uptime, turns: @session.messages.size, violations: @violations
          )
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
      @proposer ||= Propose.new(container: @container)
      @proposer.violations = @violations
      @proposer
    end

    NL_DISPATCH = [
      [/\b(?:show|print|list)\s+(?:undo\s+)?histor/i, :run_history],
      [/\b(?:why|how)\s+(?:this|that|did|was)\b/i, :run_why],
      [/\bfocus\s+(?:mode|on|off)\b|\btoggle\s+focus\b/i, :toggle_focus],
      [/\b(?:last|prev(?:ious)?)\s+(?:input|message|prompt)\b/i, :run_last],
      [/\b(?:suggest|what(?:'s|\s+is)\s+next|next\s+steps?)\b/i, :run_propose],
      [/\b(?:show|list)\s+(?:my\s+)?principles\b/i, :run_principles],
      [/\brestart\b|\bhot[\s-]?reload\b/i, :run_restart],
      [/\bui[\s-]?critique\b/i, :run_ui_critique],
      [/\bsound[\s-]?critique\b/i, :run_sound_critique],
      [/\brebuild\b/i, :run_rebuild],
      [/\bshow\s+context\b|\bcontext\s+window\b/i, :run_context],
      [/\bverifie?d?\b/i, :run_verify],
      [/\brails[\s-]?pwa[\s-]?audit\b/i, :run_rails_pwa_audit],
      [/\brails[\s-]?pwa[\s-]?fix\b/i, :run_rails_pwa_fix],
      [/\bswallow[\s-]?report\b|\berror\s+ledger\b/i, :run_swallow_report],
      [/\btoggle\s+chips?\b|\bchips?\s+(?:on|off)\b/i, :toggle_chips],
      [/\btoggle\s+dmesg\b|\bdmesg\s+(?:on|off)\b/i, :toggle_dmesg],
    ].freeze

    def handle_repl_line(line)
      stripped = line.strip
      return accept_top_suggestion if stripped.empty?
      NL_DISPATCH.each { |pat, meth| return send(meth) if stripped.match?(pat) }
      case stripped
      when "/exit", "/quit" then exit_cli
      when "/undo" then run_undo
      when "/redo" then run_redo
      when "/checkpoint" then run_checkpoint
      when "/history" then run_history
      when "/why" then run_why
      when "/focus" then toggle_focus
      when "/last" then run_last
      when "/cmd" then run_cmd
      when "/dmesg" then toggle_dmesg
      when "/chips" then toggle_chips
      when "/propose" then run_propose
      when "/principles" then run_principles
      when "/restart" then run_restart
      when "/ui-critique" then run_ui_critique
      when "/sound-critique" then run_sound_critique
      when "/rebuild" then run_rebuild
      when "/context" then run_context
      when "/verify" then run_verify
      when "/rails-pwa-audit" then run_rails_pwa_audit
      when "/rails-pwa-fix" then run_rails_pwa_fix
      when "/swallow-report" then run_swallow_report
      when "<<" then run_input(read_multiline)
      else run_input(line)
      end
    end

    def run_sound_critique
      puts @renderer.render("sound-critique: assembling audio panel", mode: :dim)
      critic = Master::Judge::Council::SoundCritique.new(agent: @agent, event_bus: @bus)
      result = critic.run
      if result.ok?
        data = result.value!
        picks = data[:cherry_picks]
        puts @renderer.render("sound-critique: #{picks.size} cherry-pick(s)", mode: :dim)
        picks.each { |p| puts @renderer.render("  cherry: #{p}", mode: :dim) }
        data[:feedback].each do |f|
          puts @renderer.render("  [#{f[:persona]}] #{f[:feedback].to_s.lines.first.to_s.strip}", mode: :dim)
        end
      else
        puts @renderer.render("sound-critique: #{result.message}", mode: :warning)
      end
    end

    def run_rebuild
      puts @renderer.render("rebuild: syntax check + session save + hot-restart", mode: :dim)
      lib_dir = File.join(Master::ROOT, "lib")
      errors = []
      changed_lib_files(lib_dir).each do |path|
        ok = system("ruby34 -c #{path} > /dev/null 2>&1")
        errors << path unless ok
      end
      if errors.any?
        errors.each { |p| puts @renderer.render("  syntax error: #{p}", mode: :warning) }
        puts @renderer.render("rebuild: aborted — fix errors first", mode: :warning)
        return
      end
      @session.save!
      puts @renderer.render("rebuild: ok — exec'ing fresh process", mode: :dim)
      $stdout.flush
      Kernel.exec(RbConfig.ruby, $PROGRAM_NAME, *ARGV)
    end

    def run_context
      query = @last_input.to_s
      puts @renderer.render("context: gathering for query=#{query[0, 60]}", mode: :dim)
      provider = Master::Ground::ContextProvider.new
      rows = provider.brief(query, limit: 8)
      if rows.empty?
        puts @renderer.render("context: nothing found", mode: :dim)
      else
        rows.each { |r| puts @renderer.render("  #{r}", mode: :dim) }
      end
      @bus&.publish("attention:context", query: query, rows: rows.size)
    end

    def run_checkpoint
      puts @renderer.render("checkpoint: snapshotting changed files", mode: :dim)
      lib_dir = File.join(Master::ROOT, "lib")
      files = changed_lib_files(lib_dir)
      cp = Master::Ground::Checkpoint.new
      result = cp.create(label: "manual", files: files)
      id = result.respond_to?(:fetch) ? result[:id] : result.to_s
      puts @renderer.render("checkpoint: #{id} (#{files.size} file(s))", mode: :dim)
    end

    def run_verify
      puts @renderer.render("verify: checking recently landed operator symbols", mode: :dim)
      plan = {
        files: %w[lib/ground/intent_router.rb lib/ground/attention_context.rb
                  lib/ground/unfinished_ledger.rb lib/ground/orchestration_policy.rb],
        symbols: %w[Master::Ground::IntentRouter Master::Ground::AttentionContext
                    Master::Ground::UnfinishedLedger Master::Ground::OrchestrationPolicy],
        callers: %w[run_sound_critique run_rebuild run_context run_checkpoint run_verify]
      }
      checker = Master::Ground::DoneChecker.new
      result = checker.call(plan)
      result.each do |key, val|
        icon = val.is_a?(TrueClass) || val == :ok ? "ok" : "!!"
        puts @renderer.render("  #{icon} #{key}", mode: val == false ? :warning : :dim)
      end
    end

    def safe_read_line
      @reader.read_line("", echo: true).chomp
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "cli.safe_read_line", event_bus: @bus)
    end

    def exit_cli
      @session.save!
      line = @renderer.closing
      puts line if line
      @running = false
    end

    def read_multiline
      lines = []
      puts @renderer.render("enter lines, blank line to send", mode: :dim)
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
        tag = msg[:role] == :user ? "you" : "master"
        content = msg[:content].to_s
        first_line = content.lines.first.to_s
        snippet = first_line.strip[0, 100]
        puts @renderer.render("  #{tag}: #{snippet}", mode: :dim)
      end
      puts
    end

    def start_background_loop
      @bg_thread = Thread.new do
        boot_scan
        loop do
          sleep IDLE_SLEEP_DEFAULT
          background_cycle unless @user_active
        end
      rescue StandardError => e
        @bus&.publish("cli:bg_error", error: e.message)
      end
    end

    def boot_scan
      lib_dir = File.join(@root, "lib")
      changed = changed_lib_files(lib_dir)
      result = changed.any? ? scan_files(changed) : @scanner.scan_dir(lib_dir, depth: :deep)
      return unless result.is_a?(Master::Result) && result.ok?

      prev = @prev_violations
      @violations = count_violations(result.value!)
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
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "cli.changed_lib_files", event_bus: @bus)
      []
    end

    def scan_files(paths)
      Result.ok(paths.map { |p| [p, @scanner.scan(p, depth: :deep)] })
    end

    def count_violations(pairs)
      pairs.sum do |_file, file_result|
        file_result.is_a?(Master::Result) && file_result.ok? ? file_result.value!.size : 0
      end
    end

    def background_cycle
      lib_dir = File.join(@root, "lib")
      result  = @scanner.scan_dir(lib_dir, depth: :deep)
      return unless result.is_a?(Master::Result) && result.ok?
      n = count_violations(result.value!)
      return if n == @violations
      @violations = n
      $stdout.puts "\nbg: #{n} violation(s)" if n.positive?
      $stdout.flush
    rescue StandardError => e
      @bus&.publish("cli:bg_error", error: e.message)
    end

    INIT_FRAMES = 20
    INIT_FRAME_MS = 0.04

    def print_repo_tree
      lines = Master::CommandRegistry.tree_lines(@root)
      return if lines.empty?
      puts @renderer.render("tree0: #{File.basename(@root)} (#{lines.size} entries)", mode: :dim)
      lines.each { |l| puts @renderer.render(l, mode: :dim) }
      puts
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "cli.print_repo_tree", event_bus: @bus)
    end

    def booted_before?
      flag = File.join(@root, ".master", "booted_once")
      File.exist?(flag)
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "cli.booted_before?", event_bus: @bus)
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
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "cli.mark_booted", event_bus: @bus)
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
        value = ok.value
        rendered = value.is_a?(Hash) ? value[:rendered] : nil
        text = rendered || value.to_s
        puts @renderer.speaker_tag
        puts text
        puts
      end
      print_cost_tooltip
      print_chips if @show_chips
    end

    def print_cost_tooltip
      now_cost = @session.cost.to_f
      delta = now_cost - @last_cost
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
      base.unshift("[/fix #{@violations}v]") if @violations.positive?
      base
    end

    def short_model(model)
      model.to_s.sub(/\Aclaude-cli:/, "").sub(/\Aweb-chat:/, "").split("/").last.to_s.sub(/:free$/, "")
    end
  end
  end
end
