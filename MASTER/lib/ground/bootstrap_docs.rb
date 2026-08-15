# frozen_string_literal: true

module Master
  module Ground
    # Agent/bootstrap prose formerly scattered across top-level .md files.
    # Served via /orient bootstrap|agents|trace|replicate|conventions — not read from disk.
    module BootstrapDocs
      PATH = File.join(Master::DATA, "bootstrap.yml").freeze

      module_function

      # /orient bootstrap is the first runtime dump START_HERE.md points at, and
      # it is an index over the other sections rather than one of them. Without
      # this key, cat_orient fell through to the nil-path branch of ORIENT_FILES
      # and answered "use /orient bootstrap" — telling you to run what you had
      # just run.
      INDEX_KEY = "bootstrap"

      def section(name)
        key = name.to_s.strip.downcase
        return index if key == INDEX_KEY

        if key == "deploy"
          require_relative "../deploy/operator_docs"
          return Master::Deploy::OperatorDocs.render_deploy
        end

        file = load_file_sections[key]
        return file if file

        SECTIONS[key] || nil
      end

      def keys
        ([INDEX_KEY] + SECTIONS.keys + load_file_sections.keys).uniq.sort
      end

      # Summaries come from each section's own first line, so the index cannot
      # drift from the sections it lists. `deploy` is read from the YAML rather
      # than through #section, which would render the whole operator doc just to
      # take one line off the top.
      def index
        rows = (keys - [INDEX_KEY]).map { |key| "  #{key.ljust(12)} #{summary_for(key)}" }
        (["bootstrap — runtime agent docs. Read one with /orient <name>:", ""] + rows).join("\n")
      end

      def summary_for(key)
        body = key == "deploy" ? load_file_sections["deploy"] : section(key)
        body.to_s.lines.first.to_s.strip
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
        Modules: cli (pipeline/CLI), fix (fix/rule/watch), review (scanner/council), voice (render/TTS), ground (constitution/memory), io (tools), trace (events/session), core (the fold).
        Flat Hierarchy: standing order aggressive_merge on every write — merge thin siblings, rename to dense Rails-parameterize slugs (snake_case, Strunk-clean tokens), OpenBSD-flat, Zeitwerk-true, Roda-tight.
        Pipeline (slash commands and inferred commands): #{Master::CLI::RuntimeMode::PIPELINE_STAGES}. Plain-language goals go to Core::Fold instead, which is the only lane the constitution judges. Every write on either lane is judged by Review::Scan::WriteGuard, which refuses one that introduces an error-severity finding — the design law is enforced on the write, not on /scan.
        VPS/deploy: OPENBSD/RUNBOOK.md (human runbook). Do not memorize /scan /fix — standing orders and Review handle most choreography.
      TEXT

      TRACE = <<~TEXT.strip
        Trace map: Trace::EventBus carries pipeline, tools, scans. CLI: /tail 20 pipeline. Web: /events/stream.
        Activity: runtime/events/activity.jsonl (/tail, /replay). Evidence: runtime/events/evidence.jsonl (/replay evidence).
        Session: .master/session.json (/history). Undo: .master/undo_journal.jsonl (/undo).
        Triage: /status, /tail, /dmesg, bin/probe. Key events: pipeline:stage_start, review:verdict, scan:progress, route:resolved.
      TEXT

      REPLICATE = <<~TEXT.strip
        Only replicate_kokoro TTS uses the Replicate API. Token: REPLICATE_API_TOKEN in /etc/master.env or ~/.config/repligen/config.json.
      TEXT

      CONVENTIONS = <<~TEXT.strip
        Inviolable law: data/soul.yml, data/rules.yml. Evidence mandatory — no hedges without command output or diffs.
        Ruby 3.3+ on OpenBSD. Style: frozen_string_literal, double quotes, no bare rescue, guard clauses, Result monad, files ≤300 lines, methods ≤10 lines.
        Shell on zsh/SSH: no sed/awk/grep/find — Ruby and zsh builtins. Scan before structural edits.
        VPS: dev@46.23.89.226, ruby34, bundle34. Operator: OPENBSD/RUNBOOK.md. Full rule index: data/CANON.md (generated).
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
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "BootstrapDocs.load_file_sections")
        {}
      end
    end
  end
end
