# frozen_string_literal: true

require_relative "cli/container"
require_relative "cli/signals"
require_relative "cli/command_ops"
require_relative "cli/thinking_indicator"
require_relative "cli/result_display"
require_relative "cli/background_scan"

require "open3"
require "reline"
require "tty-prompt"
require "tty-screen"
require "fileutils"

module Master
  module Now
    class CLI
      IDLE_SLEEP_DEFAULT = 60
      # Replay only the last few turns so startup context stays readable.
      REPLAY_TURNS = 5
      # Keep enough diagnostic lines for recent failures without flooding the UI.
      DMESG_BUFFER = 80
      MULTILINE_MAX_LINES = 500
      HISTORY_LIMIT = 2_000

      SEVERITY_ICON = {
        error: "!!",
        warning: "!",
        style: ".",
        critical: "!!"
      }.freeze
      SLASH_COMMANDS = %w[
        /help /exit /quit /undo /redo /rollback /history /grep /audit /cost /watch /why /focus /last /cmd /dmesg /chips /propose /principles /restart
        /self /phase /ui-critique /sound-critique /rebuild /context /checkpoint /verify /rails-pwa-audit /rails-pwa-fix /swallow-report
      ].freeze

      attr_reader :container

      def initialize(container:)
        @container = container
        @refs = CLI::Container.from_hash(container)
        Reline::HISTORY.clear
        load_cli_history
        setup_completion
        @running = false
        @interrupt_at = Time.now
        @last_ok = true
        @violations = 0
        @prev_violations = 0
        @violations_mutex = Mutex.new
        @bg_thread = nil
        @bg_control = Queue.new
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
        @refs.session.load! if @refs.session.exists?
        start_background_loop
        first_boot_bar
        puts @refs.renderer.splash(@refs.agent.model)
        puts @refs.renderer.session_line(@refs.session.name) if @refs.session.name
        print_repo_tree unless booted_before?
        replay_recent_turns if @refs.session.messages.any?
        run_input(initial_message) if initial_message
        @running = true
        repl_loop
      end

      def pipe(input)
        stripped = input.strip
        return empty_input(:pipe) if stripped.empty?
        run_input(stripped)
      end

      def process(input)
        run_input(input)
      end

      def run_input(input)
        return empty_input(:run_input) if input.strip.empty?

        @user_active = true
        @last_input = input
        paste = paste_like_input?(input)
        state = { streamed: false, thinking_shown: !paste }
        accumulated = +""
        on_chunk = build_stream_handler(accumulated) do |text|
          handle_stream_text(text, state)
        end

        print_thinking_indicator unless paste
        @pipeline_thread = Thread.new do
          Thread.current.report_on_exception = false
          @refs.pipeline.call(Result.ok(user_message: input, on_chunk: on_chunk))
        end
        result = begin
          @pipeline_thread.value
        rescue StandardError => _e
          Result.err("aborted", category: :abort)
        end
        display_result(result:, accumulated:, streamed: state[:streamed])
      ensure
        @pipeline_thread = nil
        stop_thinking_indicator
        @user_active = false
      end

      def empty_input(source)
        @refs.bus&.publish("cli:empty_input", source:)
        nil
      end

      def paste_like_input?(input)
        text = input.to_s
        text.lines.size > 3 || text.bytesize > 1_500
      end

      def handle_stream_text(text, state)
        if state[:thinking_shown] && $stdout.isatty
          stop_thinking_indicator
          print "\r\e[K"
          state[:thinking_shown] = false
        end
        puts @refs.renderer.speaker_tag unless state[:streamed]
        print text
        $stdout.flush
        state[:streamed] = true
      end

      private

      def set_visitor_mode_if_unauthenticated
        web_token = @refs.config&.dig("web_token")
        Fiber[:master_visitor] = true if web_token.nil? || web_token.empty?
      end

      def repl_loop
        while @running
          print prompt_for_mode
          line = safe_read_line
          break if line.nil?
          handle_repl_line(line)
        end
        stop_background_loop
        save_cli_history
        @refs.session.save!
      end

      def prompt_for_mode
        refresh_skills!
        @focus_mode ? focus_prompt : normal_prompt
      end

      def focus_prompt
        @refs.renderer.render("master$ ", mode: :dim)
      end

      def normal_prompt
        status = status_row_if_changed
        sugg = suggested_next_prompt
        tokens = @refs.session.token_est
        prompt_lines = @refs.renderer.prompt_line(
          @refs.agent.model, @refs.session.phase,
          last_ok: @last_ok, violations: violations_count, tokens: tokens, cost: @refs.session.cost
        )
        [
          (status if status),
          (@refs.renderer.render("  ↳ #{sugg}", mode: :dim) if sugg),
          prompt_lines.first,
          prompt_lines.last
        ].compact.join("\n")
      end

      def status_row_if_changed
        state = {
          turns: @refs.session.messages.size,
          violations: violations_count,
          model: @refs.agent.model,
          cost: @refs.session.cost.to_f.round(4)
        }
        return nil if @last_status_state == state

        @last_status_state = state
        @refs.renderer.status_row(uptime: @refs.renderer.uptime, turns: state[:turns], violations: state[:violations])
      end

      def suggested_next_prompt
        rows = proposer.call.first(3)
        return nil if rows.empty?

        @last_suggestion = rows.first[:action]
        rows.each_with_index.map { |row, i| "#{i + 1}. #{row[:action]} (#{row[:reason]})" }.join("  ")
      end

      def accept_top_suggestion
        return unless @last_suggestion
        puts @refs.renderer.render("↳ #{@last_suggestion}", mode: :dim)
        proposer.acted(@last_suggestion) if proposer.respond_to?(:acted)
        handle_repl_line(@last_suggestion)
      end

      def proposer
        @proposer ||= Propose.new(container: @container)
        @proposer.violations = violations_count
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
        when /\A\/(?:help|\?)(?:\s+(.+))?\z/ then run_help(Regexp.last_match(1))
        when "/exit", "/quit" then exit_cli
        when "/undo" then run_undo
        when "/rollback" then run_rollback
        when "/redo" then run_redo
        when "/checkpoint" then run_checkpoint
        when "/history" then run_history
        when /\A\/grep\s+(.+)\z/ then run_grep(Regexp.last_match(1))
        when "/audit" then run_audit
        when "/cost" then run_cost
        when /\A\/watch(?:\s+(on|off|status))?\z/ then run_watch(Regexp.last_match(1) || "status")
        when "/why" then run_why
        when "/focus" then toggle_focus
        when "/last" then run_last
        when "/cmd" then run_cmd
        when /\A\/dmesg\s+(\d+)\z/ then run_dmesg(Regexp.last_match(1).to_i)
        when "/dmesg" then toggle_dmesg
        when "/chips" then toggle_chips
        when /\A\/propose(?:\s+(.+))?\z/ then run_propose(Regexp.last_match(1))
        when "/principles" then run_principles
        when "/restart" then run_restart
        when "/self" then run_self_scan
        when /\A\/phase(?:\s+(.+))?\z/ then run_phase(Regexp.last_match(1).to_s)
        when "/ui-critique" then run_ui_critique
        when "/sound-critique" then run_sound_critique
        when "/rebuild" then run_rebuild
        when "/context" then run_context
        when "/verify" then run_verify
        when "/rails-pwa-audit" then run_rails_pwa_audit
        when "/rails-pwa-fix" then run_rails_pwa_fix
        when "/swallow-report" then run_swallow_report
        when "<<" then run_input(read_multiline)
        else stripped.start_with?("/") ? unknown_command(stripped) : run_input(line)
        end
      end

      def run_help(command = nil)
        puts @refs.renderer.render(Master::Now::CommandRegistry.help_text(command), mode: :dim)
        puts @refs.renderer.render("<< for multiline. anything else is a prompt.", mode: :dim)
      end

      def unknown_command(stripped)
        name = stripped.split(/\s/).first
        puts @refs.renderer.render("unknown command: #{name}. /help for commands.", mode: :dim)
      end

      def run_sound_critique
        puts @refs.renderer.render("sound-critique: assembling audio panel", mode: :dim)
        critic = Master::Judge::Council::SoundCritique.new(agent: @refs.agent, event_bus: @refs.bus)
        result = critic.run
        if result.ok?
          data = result.value!
          picks = data[:cherry_picks]
          puts @refs.renderer.render("sound-critique: #{picks.size} cherry-pick(s)", mode: :dim)
          picks.each { |p| puts @refs.renderer.render("  cherry: #{p}", mode: :dim) }
          data[:feedback].each do |f|
            puts @refs.renderer.render("  [#{f[:persona]}] #{f[:feedback].to_s.lines.first.to_s.strip}", mode: :dim)
          end
        else
          puts @refs.renderer.render("sound-critique: #{result.message}", mode: :warning)
        end
      end

      def run_rebuild
        puts @refs.renderer.render("rebuild: syntax check + session save + hot-restart", mode: :dim)
        lib_dir = File.join(Master::ROOT, "lib")
        errors = []
        changed_lib_files(lib_dir).each do |path|
          ok = system("ruby34", "-c", path, out: File::NULL, err: File::NULL)
          errors << path unless ok
        end
        if errors.any?
          errors.each { |p| puts @refs.renderer.render("  syntax error: #{p}", mode: :warning) }
          puts @refs.renderer.render("rebuild: aborted — fix errors first", mode: :warning)
          return
        end
        @refs.session.save!
        puts @refs.renderer.render("rebuild: ok — exec'ing fresh process", mode: :dim)
        $stdout.flush
        Kernel.exec(RbConfig.ruby, $PROGRAM_NAME, *ARGV)
      end

      def run_context
        query = @last_input.to_s
        puts @refs.renderer.render("context: gathering for query=#{query[0, 60]}", mode: :dim)
        provider = Master::Ground::ContextProvider.new
        rows = provider.brief(query, limit: 8)
        if rows.empty?
          puts @refs.renderer.render("context: nothing found", mode: :dim)
        else
          rows.each { |r| puts @refs.renderer.render("  #{r}", mode: :dim) }
        end
        @refs.bus&.publish("attention:context", query: query, rows: rows.size)
      end

      def run_checkpoint
        puts @refs.renderer.render("checkpoint: snapshotting changed files", mode: :dim)
        lib_dir = File.join(Master::ROOT, "lib")
        files = changed_lib_files(lib_dir)
        cp = Master::Ground::Checkpoint.new
        result = cp.create(label: "manual", files: files)
        id = result.respond_to?(:fetch) ? result[:id] : result.to_s
        puts @refs.renderer.render("checkpoint: #{id} (#{files.size} file(s))", mode: :dim)
      end

      def run_dmesg(lines)
        puts @refs.logging.dmesg(lines.positive? ? lines : DMESG_BUFFER)
      end

      def run_verify
        puts @refs.renderer.render("verify: checking recently landed operator symbols", mode: :dim)
        plan = {
          files: %w[lib/ground/intent_router.rb lib/ground/attention_context.rb
                    lib/ground/unfinished_ledger.rb lib/ground/orchestration_policy.rb],
          symbols: %w[Master::Ground::IntentRouter Master::Ground::AttentionContext
                      Master::Ground::UnfinishedLedger Master::Ground::OrchestrationPolicy],
          callers: %w[run_sound_critique run_rebuild run_context run_checkpoint run_verify]
        }
        checker = Master::Ground::DoneChecker.new
        result = checker.call(plan)
        result.each do |key, check_result|
          icon = check_result.is_a?(TrueClass) || check_result == :ok ? "ok" : "!!"
          puts @refs.renderer.render("  #{icon} #{key}", mode: check_result == false ? :warning : :dim)
        end
      end

      def safe_read_line
        Reline.readline("", true)&.chomp
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.safe_read_line", event_bus: @refs.bus)
      end

      def setup_completion
        Reline.completion_proc = proc do |target|
          line = Reline.line_buffer.to_s
          if line.match?(%r{\A/(scan|fix|critique)\s+})
            complete_paths(target)
          else
            SLASH_COMMANDS.select { |cmd| cmd.start_with?(target.to_s) }
          end
        end
      end

      def complete_paths(target)
        prefix = target.to_s.empty? ? "*" : "#{target}*"
        Dir.glob(File.join(@refs.root, prefix)).map do |path|
          rel = path.delete_prefix("#{@refs.root}/")
          File.directory?(path) ? "#{rel}/" : rel
        end.first(50)
      rescue StandardError
        []
      end

      def cli_history_path
        File.join(@refs.root, ".master", "cli_history")
      end

      def load_cli_history
        path = cli_history_path
        return unless File.exist?(path)

        File.readlines(path, chomp: true).last(HISTORY_LIMIT).each { |line| Reline::HISTORY << line unless line.empty? }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.load_history", event_bus: @refs.bus)
      end

      def save_cli_history
        path = cli_history_path
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, Reline::HISTORY.to_a.last(HISTORY_LIMIT).join("\n") + "\n")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.save_history", event_bus: @refs.bus)
      end

      def exit_cli
        @refs.session.save!
        save_cli_history
        line = @refs.renderer.closing
        puts line if line
        @running = false
      end

      def read_multiline
        lines = []
        puts @refs.renderer.render("enter lines, blank line to send", mode: :dim)
        loop do
          print "  "
          inner = safe_read_line
          break if inner.nil? || inner.strip.empty?
          lines << inner
          if lines.size >= MULTILINE_MAX_LINES
            puts @refs.renderer.render("multiline: capped at #{MULTILINE_MAX_LINES} lines", mode: :warning)
            break
          end
        end
        lines.join("\n")
      end

      def replay_recent_turns
        tail = @refs.session.messages.last(REPLAY_TURNS * 2)
        return if tail.empty?
        puts @refs.renderer.render("resume0: replaying last #{tail.size} messages", mode: :dim)
        tail.each do |msg|
          tag = msg[:role] == :user ? "you" : "master"
          content = msg[:content].to_s
          first_line = content.lines.first.to_s
          snippet = first_line.strip[0, 100]
          puts @refs.renderer.render("  #{tag}: #{snippet}", mode: :dim)
        end
        puts
      end

      def print_repo_tree
        lines = Master::CommandRegistry.tree_lines(@refs.root)
        return if lines.empty?
        puts @refs.renderer.render("tree0: #{File.basename(@refs.root)} (#{lines.size} entries)", mode: :dim)
        lines.each { |l| puts @refs.renderer.render(l, mode: :dim) }
        puts
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.print_repo_tree", event_bus: @refs.bus)
      end

      def booted_before?
        flag = File.join(@refs.root, ".master", "booted_once")
        File.exist?(flag)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.booted_before?", event_bus: @refs.bus)
        false
      end

      def first_boot_bar
        return unless $stdout.isatty
        flag = File.join(@refs.root, ".master", "booted_once")
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
        Master::Ground::Swallow.log(e, context: "cli.mark_booted", event_bus: @refs.bus)
      end

    end
  end
end
