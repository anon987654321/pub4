# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      HELP_TOPICS = {
        "run" => {
          summary: "natural-language task entry point",
          detail: ["/run <task>", "Routes intent through the pipeline and chooses the handler."],
        },
        "scan" => {
          summary: "deep-scan files or directories",
          detail: [
            "/scan [--dry-run] [--no-autofix] [report-filter] [path]",
            "Always runs at deep depth. Mechanical autofix (AstFixer) runs by default on auto_fix rules, then re-scans.",
            "Live output: pass1 brief → autofix → pass2/delta → full report. Checkpoints include top rules.",
            "Snapshots: .master/scan_last.txt and /tmp/master_scan_last.txt (also written on interrupt).",
            "Report-only: --dry-run. Skip writes but keep full rule set: --no-autofix. Disable via MASTER_SCAN_AUTOFIX=0.",
            "Report filters / profiles: full, core, critical, cosmetic, aesthetic (aliases: pixel, ui, ux, design).",
            "Path aliases: rails, rails/brgen, face, web, self, master. Also RAILS/<app> from repo root.",
          ],
        },
        "mode" => {
          summary: "session adherence posture (loose|balanced|strict)",
          detail: ["/mode", "/mode list", "/mode balanced", "Usually inferred; caps fix passes and default scan profile."],
        },
        "map" => {
          summary: "principle_map: fossil→runtime rule coverage",
          detail: ["/map", "/map gaps|aesthetic|covered|integrity|provenance", "/map <principle_id>"],
        },
        "maturity" => {
          summary: "maturity scorecard: what's proven working, not just claimed",
          detail: ["/maturity", "/maturity verified|smoke|broken", "/maturity <subsystem_id>"],
        },
        "laws" => {
          summary: "constitutional self-test: the 8 laws, plain-English, decoded",
          detail: ["/laws", "/laws <LAW_NAME>", "Sourced from data/rules.yml so it can't drift from what SelfTest enforces."],
        },
        "through" => {
          summary: "full singularity pass (auto-sequenced)",
          detail: [
            "Natural language preferred: \"run master through itself\", \"improve rails/brgen\", \"through rails\".",
            "Sequence: mode → aesthetic scan → deep scan → fix → re-scan → critique.",
            "Optional slash: /through [rails|master|face|path] [--dry-run] [--no-critique]",
          ],
        },
        "workflow" => {
          summary: "alias of through (inferred full pass)",
          detail: ["Same as /through — prefer plain language over slash commands."],
        },
        "self" => {
          summary: "scan MASTER itself",
          detail: ["/self", "Runs the MASTER self-scan with stream output."],
        },
        "core" => {
          summary: "run core fold smoke test",
          detail: ["/core", "Runs spec/core_smoke.rb — Effect → Constitution → World loop."],
        },
        "fix" => {
          summary: "run or preview fixes for a target",
          detail: ["/fix [path]", "/fix --dry-run [path]", "/fix preview [path]", "Background control lives under /watch on|off|status."],
        },
        "status" => {
          summary: "show one-frame service and repo health",
          detail: ["/status", "Shows mode line, service state, git divergence, fix loop state, last pipeline stage, review verdict, recent events."],
        },
        "orient" => {
          summary: "authority map and reading tiers",
          detail: ["/orient", "/orient <soul|rules|limits|bootstrap|trace|…>", "Pipeline map, runtime bootstrap, constitution file index."],
        },
        "tools" => {
          summary: "list Reach agent tools",
          detail: ["/tools", "Shows Builder TOOL_MAP and data/tools.yml."],
        },
        "replay" => {
          summary: "replay operational event history",
          detail: ["/replay [N]", "/replay turn", "/replay failures [N]", "/replay commit <sha>", "/replay evidence [N]", "/replay YYYY-MM-DD", "Reads runtime activity JSONL and turn traces."],
        },
        "graph" => {
          summary: "show file importance via dependency graph",
          detail: ["/graph <file>", "Blast radius, ranked neighbours, and indexed symbols for a path."],
        },
        "resync" => {
          summary: "repair local divergence from origin/main",
          detail: ["/resync [--dry-run]", "Tags current HEAD, fetches, then resets and restarts unless dry-run is set."],
        },
        "tail" => {
          summary: "show recent event log lines",
          detail: ["/tail [N] [pattern]", "Filters runtime event JSONL by count and optional pattern."],
        },
        "why" => {
          summary: "explain a law, rule, anti-pattern, or style key",
          detail: ["/why <law|scan_rule|anti_pattern|style.key>"],
        },
        "propose" => {
          summary: "show next-action proposals",
          detail: ["/propose", "Ranks likely next actions from session, git, phase, and violation signals."],
        },
        "rules" => {
          summary: "list registered scan rules",
          detail: ["/rules list", "Shows rule IDs, severity, and implementation class."],
        },
        "edge-cases" => {
          summary: "generate edge-case test stubs",
          detail: ["/edge-cases <ruby-file>", "Creates skipped tests for nil, empty, max, unicode, invalid JSON, truncation, and injection inputs."],
        },
        "analyze-self" => {
          summary: "summarize recurring self-improvement signals",
          detail: ["/analyze-self", "Reads the feedback ledger and reports repeated corrections, provider errors, and failing tools."],
        },
        "rollback" => {
          summary: "revert the last recorded change",
          detail: ["/rollback", "Uses the undo stack; pipeline failure rollback remains automatic."],
        },
        "audit" => {
          summary: "show changed files this session",
          detail: ["/audit", "Lists git diff line counts for changed files."],
        },
        "snapshot" => {
          summary: "publish MASTER + OPERATOR codebase snapshots",
          detail: [
            "/snapshot",
            "Writes full MASTER + OPERATOR snapshots to ~/Downloads.",
            "Tree listing then every file verbatim (no truncation).",
            "Outputs: MASTER_snapshot.md and MASTER_snapshot_YYYY-MM-DD.md.",
          ],
        },
        "grep" => {
          summary: "search session history",
          detail: ["/grep <pattern>", "Returns matching user/master turns from the current session."],
        },
        "watch" => {
          summary: "control background watching",
          detail: ["/watch on", "/watch off", "/watch status"],
        },
        "help" => {
          summary: "show command summaries or details",
          detail: ["/help", "/help <command>"],
        },
        "fold" => {
          summary: "run a coding goal through the core Fold (rebuild runtime)",
          detail: ["/fold <goal>", "Routes one goal to core/; streams turns as core:turn events."],
        },
        "domain" => {
          summary: "inspect or sync a pub4 subdomain cluster",
          detail: ["/domain <name>", "Names: marketplace playlist takeaway tv maps amber bsdports brgen …"],
        },
        "music" => {
          summary: "open Radio Bergen or Dilla pocket on the face",
          detail: ["/music radio", "/music dilla", "Infer: say 'play radio' or 'dilla pocket'."],
        },
        "dilla" => {
          summary: "render Dilla audio or perfect it via MASTER council",
          detail: [
            "/dilla generate [--style dilla] [--bars N]",
            "/dilla metrics [path.wav]",
            "/dilla crit [path.wav] — multi-persona panel, multi-solution ideation, cherry-pick",
            "Also /dilla-critique and /sound-critique. Engine is render+meters only.",
          ],
        },
        "review" => {
          summary: "multi-reviewer code review on a path or diff",
          detail: ["/review <path>", "/review --staged", "Runs reviewer personas against the target."],
        },
        "critique" => {
          summary: "single-pass critique of code or a change set",
          detail: ["/critique <path>", "Lighter than /review — one structured pass."],
        },
        "model" => {
          summary: "show or switch the active LLM model",
          detail: ["/model", "/model <name>", "Uses routing from data/models.yml."],
        },
        "reasoning" => {
          summary: "prompt-wrapping strategy (direct|react|rewoo|code_agent)",
          detail: [
            "/reasoning", "/reasoning react",
            "Sets config.reasoning_mode; templates live in data/prompts/mode_<name>.yml.",
            "Distinct from /mode, which is the loose|balanced|strict session posture.",
          ],
        },
        "memory" => {
          summary: "read or write durable operator memory records",
          detail: ["/memory list", "/memory show <key>", "/memory write <key> …"],
        },
        "doctor" => {
          summary: "run bin/doctor health checks",
          detail: ["/doctor", "Provider keys, disk, git, web smoke hints.", "/doctor --fix repairs known config drift (e.g. dangling principle_map.yml rule_ids)."],
        },
        "pair" => {
          summary: "issue or redeem a pairing code for messaging tools",
          detail: [
            "/pair issue [label]",
            "/pair <code> — redeem (also POST /pair)",
            "/pair status", "/pair list", "/pair revoke <token>",
            "Paired visitors get the messaging profile (fetch + personal memory), never Shell.",
          ],
        },
        "security-audit" => {
          summary: "runtime exposure: pairing, profiles, visitor slash, gateway",
          detail: ["/security-audit", "Distinct from /doctor. Reports whether the public face can reach personal tools without pairing."],
        },
        "commit" => {
          summary: "LLM-authored git commit of the current diff (review-gated)",
          detail: ["/commit", "Shows this notice first -- re-run as /commit --confirm to actually run git add -u + git commit."],
        },
        "reap" => {
          summary: "kill suspended bin/cli and tts-worker processes",
          detail: ["/reap", "Ctrl-Z leaves stopped ruby on 1GB hosts. Auto-reaps on boot when constrained."],
        },
        "rebuild" => {
          summary: "syntax-check lib/, save session, hot-restart CLI",
          detail: ["/rebuild", "Web: touches web/tmp/restart.txt when run from MASTER/web tree."],
        },
        "gateway" => {
          summary: "show multi-channel gateway status",
          detail: ["/gateway", "cli web irc matrix api adapter states."],
        },
        "shell" => {
          summary: "run one guarded shell command",
          detail: ["/shell <command>", "Uses Io::Shell with governor tier checks."],
        },
        "plan" => {
          summary: "read or publish the active implementation plan",
          detail: ["/plan", "/plan show", "Ground::ActivePlan markdown in repo."],
        },
        "clear" => {
          summary: "clear the current session transcript",
          detail: ["/clear", "Does not undo file changes."],
        },
        "save" => {
          summary: "persist session to disk",
          detail: ["/save", "Writes session JSON under runtime/."],
        },
        "diag" => {
          summary: "compact diagnostics snapshot",
          detail: ["/diag", "Breaker, homeostat, last errors."],
        },
      }.freeze

      def help_text(command = nil)
        key = command.to_s.strip.sub(/\A\//, "")
        return help_summary if key.empty?

        topic = HELP_TOPICS[key]
        return "help: unknown command /#{key}" unless topic

        (["/#{key} - #{topic[:summary]}"] + topic[:detail]).join("\n")
      end

      COMMAND_CATEGORIES = {
        "session" => %w[clear save history grep audit tokens cost undo rollback redo],
        "work" => %w[scan fix through workflow review critique self kernel status mode map maturity replay graph resync tail edge-cases],
        "agent" => %w[run reasoning task persona btw shell gateway plan rebuild],
        "system" => %w[orient tools tree diff commit snapshot diag reload propose context verify doctor pair security-audit help domain fold],
        "infer" => [],
        "media" => %w[music dilla],
      }.freeze

      CLI_ONLY_SLASH = %w[
        /exit /quit /grep /audit /cost /focus /last /cmd /dmesg /chips /phase
        /ui-critique /sound-critique /dilla-critique /rebuild /context /checkpoint /verify
        /rails-pwa-audit /rails-pwa-fix /swallow-report /restart /principles /self
        /watch /why /config /rules /analyze-self
      ].freeze

      def slash_commands
        registry = HELP_TOPICS.keys.map { |k| "/#{k}" }
        infer_cmds = infer_command_names.map { |k| "/#{k}" }
        (registry + infer_cmds + CLI_ONLY_SLASH).uniq.sort
      end

      def infer_command_names
        path = Master.data_path("patterns.yml")
        return [] unless File.exist?(path)
        data = Master.load_yaml(path) || {}
        (data.dig("infer", "commands") || {}).keys.map(&:to_s)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.infer_command_names")
        []
      end

      def infer_help_lines
        path = Master.data_path("patterns.yml")
        return [] unless File.exist?(path)
        data = Master.load_yaml(path) || {}
        (data.dig("infer", "commands") || {}).map do |name, spec|
          sample = Array(spec["patterns"]).first.to_s.gsub(/\\b/, "").tr("^$", "")[0, 48]
          "  say: #{sample}… → /#{name}"
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.infer_help_lines")
        []
      end

      def help_summary
        lines = []
        COMMAND_CATEGORIES.each do |category, cmds|
          rows = cmds.filter_map do |cmd|
            topic = HELP_TOPICS[cmd]
            next unless topic
            "[#{category}] /#{cmd} - #{topic[:summary]}"
          end
          lines.concat(rows)
        end
        uncategorized = HELP_TOPICS.keys - COMMAND_CATEGORIES.values.flatten
        uncategorized.each { |cmd| lines << "/#{cmd} - #{HELP_TOPICS[cmd][:summary]}" }
        infer_lines = infer_help_lines
        lines << "" << "natural language (infer):" if infer_lines.any?
        lines.concat(infer_lines.first(12))
        (lines + ["/help <command> - show details"]).join("\n")
      end
    end
  end
end
