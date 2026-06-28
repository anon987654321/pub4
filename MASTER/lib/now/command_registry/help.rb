# frozen_string_literal: true

module Master
  module Now
    module CommandRegistry
      module_function

      HELP_TOPICS = {
        "run" => {
          summary: "natural-language task entry point",
          detail: ["/run <task>", "Routes intent through the pipeline and chooses the handler."]
        },
        "scan" => {
          summary: "deep-scan files or directories",
          detail: ["/scan [--dry-run] [report-filter] [path]", "Always runs at deep depth (DEEP_SCAN_ONLY). Report filters only — not depth tiers: full, core, axioms, solid, critical, cosmetic (aliases: style, hygiene, perfection). Use --profile NAME for explicit selection. Dry-run reports findings without changes."]
        },
        "self" => {
          summary: "scan MASTER itself",
          detail: ["/self", "Runs the MASTER self-scan with stream output."]
        },
        "kernel" => {
          summary: "run kernel fold smoke test",
          detail: ["/kernel", "Runs kernel/spec/kernel_smoke.rb — Effect → Constitution → World loop."]
        },
        "fix" => {
          summary: "run or preview fixes for a target",
          detail: ["/fix [path]", "/fix --dry-run [path]", "/fix preview [path]", "Background control lives under /watch on|off|status."]
        },
        "status" => {
          summary: "show one-frame service and repo health",
          detail: ["/status", "Shows mode line, service state, git divergence, fix loop state, last pipeline stage, review verdict, recent events."]
        },
        "orient" => {
          summary: "authority map and reading tiers",
          detail: ["/orient", "/orient <soul|rules|limits|…>", "Pipeline map, TRACE.md pointer, constitution file index."]
        },
        "tools" => {
          summary: "list Reach agent tools and CLI media commands",
          detail: ["/tools", "Shows Builder TOOL_MAP, /postpro /repligen /video, and data/tools.yml."]
        },
        "replay" => {
          summary: "replay operational event history",
          detail: ["/replay [N]", "/replay turn", "/replay failures [N]", "/replay commit <sha>", "/replay evidence [N]", "/replay YYYY-MM-DD", "Reads runtime activity JSONL and turn traces."]
        },
        "graph" => {
          summary: "show file importance via dependency graph",
          detail: ["/graph <file>", "Blast radius, ranked neighbours, and indexed symbols for a path."]
        },
        "resync" => {
          summary: "repair local divergence from origin/main",
          detail: ["/resync [--dry-run]", "Tags current HEAD, fetches, then resets and restarts unless dry-run is set."]
        },
        "tail" => {
          summary: "show recent event log lines",
          detail: ["/tail [N] [pattern]", "Filters runtime event JSONL by count and optional pattern."]
        },
        "why" => {
          summary: "explain a law, rule, anti-pattern, or style key",
          detail: ["/why <law|scan_rule|anti_pattern|style.key>"]
        },
        "propose" => {
          summary: "show next-action proposals",
          detail: ["/propose", "Ranks likely next actions from session, git, phase, and violation signals."]
        },
        "rules" => {
          summary: "list registered scan rules",
          detail: ["/rules list", "Shows rule IDs, severity, and implementation class."]
        },
        "edge-cases" => {
          summary: "generate edge-case test stubs",
          detail: ["/edge-cases <ruby-file>", "Creates skipped tests for nil, empty, max, unicode, invalid JSON, truncation, and injection inputs."]
        },
        "analyze-self" => {
          summary: "summarize recurring self-improvement signals",
          detail: ["/analyze-self", "Reads the feedback ledger and reports repeated corrections, provider errors, and failing tools."]
        },
        "workflow" => {
          summary: "scan, preview fix, and deliberation (usually inferred)",
          detail: ["Say: run this through MASTER, or: full pass on lib/foo.rb", "/workflow <path> — explicit escape hatch only."]
        },
        "rollback" => {
          summary: "revert the last recorded change",
          detail: ["/rollback", "Uses the undo stack; pipeline failure rollback remains automatic."]
        },
        "audit" => {
          summary: "show changed files this session",
          detail: ["/audit", "Lists git diff line counts for changed files."]
        },
        "snapshot" => {
          summary: "publish MASTER + DEPLOY codebase snapshots",
          detail: [
            "/snapshot",
            "Writes full MASTER + DEPLOY snapshots to ~/Downloads.",
            "Tree listing then every file verbatim (no truncation).",
            "Outputs: MASTER_snapshot.md and MASTER_snapshot_YYYY-MM-DD.md."
          ]
        },
        "grep" => {
          summary: "search session history",
          detail: ["/grep <pattern>", "Returns matching user/master turns from the current session."]
        },
        "watch" => {
          summary: "control background watching",
          detail: ["/watch on", "/watch off", "/watch status"]
        },
        "help" => {
          summary: "show command summaries or details",
          detail: ["/help", "/help <command>"]
        },
        "video" => {
          summary: "long-form cinematic video via VideoChain",
          detail: [
            "/video [--backend kling|happyhorse|cogvideox|minimax|animatediff|animatediff_camera]",
            "[--minutes N] [--critique] [--vision-critique] [--per-chunk-critique]",
            "[--auto-retry] [--max-retries N] [--lora ID]",
            "[--motion-stack preset1,preset2] [--motion-preset NAME] <prompt>",
            "Standalone: bundle exec ruby bin/video (see REPLICATE.md).",
          ]
        },
        "motion-dataset" => {
          summary: "bootstrap Motion LoRA training clips",
          detail: [
            "/motion-dataset --preset slow_dolly_push_in --subject \"character description\"",
            "[--clips 12] [--backend kling] [--lora ID]",
            "Presets: data/comfyui/motion_lora_presets.yml",
          ]
        },
        "lora-train" => {
          summary: "train a character Flux LoRA from photos and videos",
          detail: [
            "/lora-train --name ragnhild [--destination owner/model] [--trigger ragnhild]",
            "[--split-all] splits every video frame; curates to 12-18 for training.",
            "[--local] writes ostris/ai-toolkit config + run_train.sh (no Replicate).",
            "[--ai-toolkit PATH] [--steps 1000] [--rank 16] [--use-all-frames] [--prepare-only]",
            "Standalone: bundle exec ruby bin/video lora-train …",
          ]
        },
        "social-sim" => {
          summary: "closed synthetic inbox sim (NPC personas, metrics, no real messengers)",
          detail: [
            "/social-sim init --subject ragnhild [--personas 12]",
            "/social-sim tick --hours 24 [--auto ghost|busy|not_interested]",
            "/social-sim tui | stats | dashboard | visuals [--lora basicfeatures/ragnhild]",
            "Standalone: bundle exec ruby bin/social_sim help",
          ]
        },
        "photograph" => {
          summary: "Flux photo + kodak_portra postpro",
          detail: ["/photograph <seed>", "Attach a reference image in web chat for vision-guided refinement."]
        },
        "prompt" => {
          summary: "refine a generation prompt (photo or video)",
          detail: ["/prompt <seed>", "/prompt photo <seed>", "/prompt video <seed>"]
        },
        "repligen" => {
          summary: "Replicate image/video generation CLI",
          detail: ["/repligen generate <model> <prompt>", "/repligen sync|search|stats …"]
        },
        "postpro" => {
          summary: "film-stock post-processing on images",
          detail: ["/postpro --input path --output path --preset portrait --stock kodak_portra"]
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
        "work" => %w[scan fix workflow review critique self kernel status replay graph resync tail edge-cases],
        "agent" => %w[run mode task persona btw shell gateway],
        "system" => %w[orient tools tree diff commit snapshot diag reload propose context verify doctor help],
        "infer" => [],
        "media" => %w[photograph repligen postpro prompt video motion-dataset lora-train social-sim],
      }.freeze

      CLI_ONLY_SLASH = %w[
        /exit /quit /grep /audit /cost /focus /last /cmd /dmesg /chips /phase
        /ui-critique /sound-critique /rebuild /context /checkpoint /verify
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
      rescue StandardError
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
      rescue StandardError
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
