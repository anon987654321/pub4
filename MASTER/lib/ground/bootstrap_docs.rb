# frozen_string_literal: true

module Master
  module Ground
    # Agent/bootstrap prose formerly scattered across top-level .md files.
    # Served via /orient bootstrap|agents|trace|replicate|conventions — not read from disk.
    module BootstrapDocs
      PATH = File.join(Master::DATA, "bootstrap.yml").freeze

      module_function

      def section(name)
        key = name.to_s.strip.downcase
        if key == "deploy"
          require_relative "../deploy/operator_docs"
          return Master::Deploy::OperatorDocs.render_deploy
        end

        file = load_file_sections[key]
        return file if file

        SECTIONS[key] || nil
      end

      def keys
        (SECTIONS.keys + load_file_sections.keys).uniq.sort
      end

      QUICKSTART = <<~TEXT.strip
        MASTER mental model: propose, validate against the constitution, execute with evidence, learn.
        Reconnaissance-then-edit: read full targets before patching. Standing orders lint written paths and audit lib/ for drift.
        Natural language works: "check my edits", "fix this file", "run through master". Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK.
        Smoke: bin/probe. Full readiness: bin/probe all. Deploy integrity: bin/probe integrity. Ferrum crawl: bin/probe crawl-browser (MASTER_CRAWL_BROWSER=1 on macOS).
        VPS: ruby34, bundle34 under /home/dev/pub4/MASTER. After web/ edits: doas rcctl restart master.
      TEXT

      AGENTS = <<~TEXT.strip
        Bootstrap for coding agents (Cursor, Claude Code, Codex, Aider). Authority: data/soul.yml → data/rules.yml → CONVENTIONS (via /orient conventions) → this runtime.
        Modules: now (pipeline/CLI), loop (fix/rule/watch), judge (scanner/council), voice (render/TTS), ground (constitution/memory), reach (tools), trace (events/session).
        Flat Hierarchy: standing order aggressive_merge on every write — merge thin siblings, rename to dense Rails-parameterize slugs (snake_case, Strunk-clean tokens), OpenBSD-flat, Zeitwerk-true, Roda-tight.
        Pipeline: #{Master::Now::RuntimeMode::PIPELINE_STAGES}. Review runs Council when enabled, then Lint on written paths, then Prune.
        VPS/deploy: DEPLOY/OPERATOR.md (human runbook). Do not memorize /scan /fix — standing orders and Review handle most choreography.
      TEXT

      TRACE = <<~TEXT.strip
        Trace map: Trace::EventBus carries pipeline, tools, scans. CLI: /tail 20 pipeline. Web: /events/stream.
        Activity: runtime/events/activity.jsonl (/tail, /replay). Evidence: runtime/events/evidence.jsonl (/replay evidence).
        Session: .master/session.json (/history). Undo: .master/undo_journal.jsonl (/undo).
        Triage: /status, /tail, /dmesg, bin/probe. Key events: pipeline:stage_start, review:verdict, scan:progress, route:resolved.
      TEXT

      REPLICATE = <<~TEXT.strip
        Replicate API is used only by the replicate_kokoro TTS engine. Token: REPLICATE_API_TOKEN in /etc/master.env or ~/.config/repligen/config.json.
      TEXT

      CONVENTIONS = <<~TEXT.strip
        Inviolable law: data/soul.yml, data/rules.yml. Evidence mandatory — no hedges without command output or diffs.
        Ruby 3.3+ on OpenBSD. Style: frozen_string_literal, double quotes, no bare rescue, guard clauses, Result monad, files ≤300 lines, methods ≤10 lines.
        Shell on zsh/SSH: no sed/awk/grep/find — Ruby and zsh builtins. Scan before structural edits.
        VPS: dev@46.23.89.226, ruby34, bundle34. Operator: DEPLOY/OPERATOR.md. Full rule index: data/CANON.md (generated).
      TEXT

      SECTIONS = {
        "quickstart" => QUICKSTART,
        "agents" => AGENTS,
        "trace" => TRACE,
        "replicate" => REPLICATE,
        "conventions" => CONVENTIONS,
      }.freeze

      def load_file_sections
        return {} unless File.file?(PATH)

        data = Master.load_yaml(PATH)
        data.is_a?(Hash) ? data.fetch("sections", {}) : {}
      rescue StandardError
        {}
      end
    end
  end
end
