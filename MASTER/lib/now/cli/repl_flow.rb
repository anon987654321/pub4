# frozen_string_literal: true

require_relative "../../ground/orchestration_policy"
require_relative "command_handlers"

module Master
  module Now
    class CLI
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
        @refs.renderer.render("#{@refs.renderer.prompt_token} ", mode: :dim)
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
          prompt_lines.last,
        ].compact.join("\n")
      end

      def status_row_if_changed
        state = {
          turns: @refs.session.messages.size,
          violations: violations_count,
          model: @refs.agent.model,
          cost: @refs.session.cost.to_f.round(4),
        }
        return if @last_status_state == state

        @last_status_state = state
        @refs.renderer.status_row(uptime: @refs.renderer.uptime, turns: state[:turns], violations: state[:violations])
      end

      def suggested_next_prompt
        rows = proposer.call.first(3)
        return if rows.empty?

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
        [/\b(?:analyze|analyse|audit|scan)\b.*\b(?:every|all|each)\b.*\bfiles?\b/i, :run_bounded_repo_scan],
        [/\b(?:autofix|autoalign|autoimplement)\b.*\b(?:recursively|recursive|every|all)\b/i, :run_bounded_repo_scan],
        [/\A(?:hi|hello|hey|yo|good (?:morning|afternoon|evening))[\s!.?]*\z/i, :run_chitchat],
        [/\b(?:show|print|list)\s+(?:undo\s+)?histor/i, :run_history],
        [/\b(?:why|how)\s+(?:this|that)\s+(?:fail(?:ed)?|break|broke|error|wrong|happen(?:ed)?)\b/i, :run_why],
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
        when "/snapshot" then run_snapshot
        when "/reap" then run_reap
        when "/verify" then run_verify
        when "/rails-pwa-audit" then run_rails_pwa_audit
        when "/rails-pwa-fix" then run_rails_pwa_fix
        when "/swallow-report" then run_swallow_report
        when "<<" then run_input(read_multiline)
        else stripped.start_with?("/") ? run_input(stripped) : handle_plain_language_line(line)
        end
      end

      def run_chitchat
        puts @refs.renderer.render("hello. MASTER is awake. use /cmd for commands or ask for a scan.", mode: :dim)
      end

      WORKFLOW_INTENTS = %i[
        wire_existing_module refactor_to_ruby create_facade codify_policy
        continue_prior_plan run_full_workflow
      ].freeze

      def handle_plain_language_line(line)
        if (refusal = host_refusal_for(line))
          puts @refs.renderer.render(refusal, mode: :warning)
          return
        end

        route = inferred_intent_route(line)
        return run_input(line) unless route

        case route[:intent]
        when :scan_then_fix_then_commit
          target = inferred_target_path(line)
          run_workflow(target)
          run_commit
        when :scan_then_fix
          target = inferred_target_path(line)
          run_work_command("scan", target)
          run_work_command("fix", target)
        when :scan_target
          run_work_command("scan", inferred_target_path(line))
        when :scan_git_changes
          run_scan_git_changes
        when :scan_fix_lint
          target = inferred_target_path(line)
          run_workflow(target)
          run_lint(target)
        when :why_axioms
          run_why
          run_axioms
        when :run_ui_review
          run_ui_critique
        when :run_sound_review
          run_sound_critique
        when :verify_patch_landed
          run_verify
        when :write_repo_changes
          run_commit
          run_push if route[:push]
        when :bounded_repo_scan
          run_bounded_repo_scan(autofix: route[:autofix])
        when *WORKFLOW_INTENTS
          target = inferred_target_path(line)
          run_workflow(target)
          run_commit if route[:risk] != :low
        else
          run_input(line)
        end
      end

      def run_reap
        n = Master::Ground::HostBudget.reap_suspended_ruby!
        msg = n.positive? ? "reap: #{n} suspended ruby process(es) killed" : "reap: no suspended ruby processes"
        puts @refs.renderer.render(msg, mode: :dim)
      end

      def run_bounded_repo_scan(autofix: false)
        puts @refs.renderer.render("scan0: lib/ only (DEPLOY via /scan ../DEPLOY/rails — host budget)", mode: :dim)
        run_work_command("scan", "lib")
        run_work_command("fix", "lib") if autofix
      end

      def host_refusal_for(line)
        Master::Ground::HostBudget.refuse_heavy_prompt?(line)
      rescue StandardError
        nil
      end

      def host_repo_wide_request?(text)
        Master::Ground::HostBudget.repo_wide_request?(text)
      rescue StandardError
        false
      end

      def run_workflow(target)
        run_work_command("workflow", target)
      end

      def run_work_command(command, args = "")
        run_input(["/#{command}", args.to_s.strip].join(" ").strip)
      end

      def inferred_intent_route(line)
        text = line.to_s.strip
        if host_repo_wide_request?(text)
          return { intent: :bounded_repo_scan, autofix: text.match?(/\b(?:autofix|autoalign|autoimplement)\b/i), risk: :high }
        end
        if text.match?(/\b(?:run|put|send|take)\s+(?:this|it|that)?\s*through\s+master\b/i) ||
           text.match?(/\b(?:full\s+)?(?:pass|tribunal)\b/i)
          return { intent: :run_full_workflow, risk: :medium }
        end
        return { intent: :scan_then_fix_then_commit, risk: :high } if text.match?(/\A.*\bscan\b.*\bfix\b.*\bcommit\b/i)
        return { intent: :scan_fix_lint, risk: :medium } if text.match?(/\A(?:clean|tidy|polish)\b/i)
        return { intent: :scan_target, risk: :low } if text.match?(/\A(?:check|audit)\b/i)
        return { intent: :scan_git_changes, risk: :low } if text.match?(/\b(?:review\s+my\s+changes?|check\s+what\s+I\s+edited|what\s+did\s+I\s+change)\b/i)
        return { intent: :why_axioms, risk: :low } if text.match?(/\A(?:explain|why|what)\b/i)
        return { intent: :scan_then_fix, risk: :medium } if text.match?(/\Afix\b/i)
        return { intent: :run_ui_review, risk: :low } if text.match?(/\A(?:ui[\s-]?)?critique\b/i)
        return { intent: :verify_patch_landed, risk: :low } if text.match?(/\A(?:verify|confirm)\b/i)
        return { intent: :write_repo_changes, risk: :high, push: text.match?(/\bpush\b/i) } if text.match?(/\b(?:commit|save|ship|push)\b/i)

        policy = @intent_policy ||= Master::Ground::OrchestrationPolicy.new
        route = policy.evaluate(text)
        route[:intent] == :unknown ? nil : route
      rescue StandardError
        nil
      end

      def inferred_target_path(line)
        text = line.to_s
        text[%r{\b([\w./-]+\.(?:rb|js|ts|yml|yaml|md|erb|css|scss|json))\b}, 1] || "."
      end

      def run_commit
        puts @refs.renderer.render(Master::Now::CommandRegistry.dispatch_commit(@refs.agent, @refs.root), mode: :dim)
      rescue StandardError => e
        puts @refs.renderer.render("commit: #{e.message}", mode: :warning)
      end

      def run_push
        out, status = Master::Reach::Exec.capture2e("git", "-C", @refs.root, "push")
        message = status.success? ? out.strip : "push: #{out.strip}"
        puts @refs.renderer.render(message.empty? ? "push: ok" : message, mode: status.success? ? :dim : :warning)
      rescue StandardError => e
        puts @refs.renderer.render("push: #{e.message}", mode: :warning)
      end

      def run_axioms
        puts @refs.renderer.render(Master::Now::CommandRegistry.dispatch_axioms(scanner: @refs.scanner, root: @refs.root), mode: :dim)
      rescue StandardError => e
        puts @refs.renderer.render("axioms: #{e.message}", mode: :warning)
      end

      def run_scan_git_changes
        out, status = Master::Reach::Exec.capture2e("git", "-C", @refs.root, "diff", "--name-only", "HEAD")
        unless status.success?
          puts @refs.renderer.render("scan: git diff failed — #{out.strip}", mode: :warning)
          return
        end
        paths = out.lines.map(&:strip).reject(&:empty?).first(20)
        if paths.empty?
          puts @refs.renderer.render("scan: no uncommitted changes", mode: :dim)
          return
        end
        paths.each { |path| run_work_command("scan", path) }
      end

      def run_lint(target)
        ctx = Master::Now::PipelineContext.build(user_message: "lint #{target}", output: "", written_files: [File.expand_path(target, @refs.root)])
        lint = Master::Now::Stages::Lint.new(scanner: @refs.scanner, config: @refs.config, root: @refs.root, event_bus: @refs.bus)
        result = lint.call(ctx)
        report = result.ok? ? result.value!.lint_report : []
        text = if report.empty?
                 "lint: clean"
               else
                 "lint: #{report.size} finding(s)"
               end
        puts @refs.renderer.render(text, mode: :dim)
      rescue StandardError => e
        puts @refs.renderer.render("lint: #{e.message}", mode: :warning)
      end
    end
  end
end
