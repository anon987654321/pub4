# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      # The council, inside the loop. A pass that found violations asks the
      # panel what is wrong with the files those violations are in, has it
      # propose competing repairs, and hands the strongest of them to the rule
      # loop as context. A critique that ends in prose changes nothing; this is
      # the seam where it becomes a repair the fixer can weigh.
      #
      # It runs at most once per pass and only while the pass has time left,
      # because it is the most expensive call in the loop: a panel over a dozen
      # files costs minutes, and a repair that arrives after the deadline is a
      # repair nobody applies.
      class CouncilRound
        FILES_PER_ROUND = 12
        IMPROVEMENT_RULE_ID = "COUNCIL_IMPROVEMENT"
        IMPROVEMENT_RULE = Data.define(:id) do
          def severity = :warning
        end
        IMPROVEMENT_SEVERITY = :warning
        MAX_IMPROVEMENT_FINDINGS = Integer(ENV.fetch("MASTER_FIX_IMPROVEMENT_FINDINGS", "4"))
        DESTRUCTIVE_IMPROVEMENT = /\b(?:delete|remove|drop|erase|discard)\b/i.freeze
        SAFE_REMOVE_IMPROVEMENT = /\bremove\s+(?:the\s+)?(?:unused|dead|redundant)\s+(?:argument|parameter|import|require)\b/i.freeze
        LINE_RE = /\b(?:line|ln)\s*#?\s*(\d+)\b/i.freeze
        SYMBOL_RE = /\b(class|module|def)\s+([A-Za-z_]\w*[!?=]?)/i.freeze

        def initialize(agent:, root:, bus: nil, discipline: nil)
          @agent = agent
          @root = root
          @bus = bus
          @discipline = discipline || Master::Fix::ConvergenceDiscipline.new(root:, bus:)
        end

        # nil when there is nothing to argue about or nobody to argue with, so
        # the caller can treat "no council" and "council said nothing" alike.
        def run(files:, pass:, deadline:)
          return if @agent.nil? || files.empty? || Time.now >= deadline

          result = critique(files.first(FILES_PER_ROUND))
          return unless result&.ok?

          value = result.value!
          return if Array(value[:cherry_picks]).empty?

          publish(value, pass:, files:)
          value
        end

        # A clean deterministic scan is not a proof of design quality or code quality.
        # One exploratory council pass gives /fix the same opportunity we use when
        # reviewing a change by hand: find a real micro-smell, simplify it, and then
        # let LawLoop apply the repair under the normal verification gates.
        # Only the first clean streak pass asks, so the next pass can confirm the
        # result without paying for the same exploratory review twice.
        def improve(files:, pass:, deadline:)
          return if @agent.nil? || files.empty? || Time.now >= deadline

          selected = rotating_files(files, pass)
          result = critique(selected)
          return unless result&.ok?

          value = result.value!
          findings = improvement_findings(value, selected).first(MAX_IMPROVEMENT_FINDINGS)
          @bus&.publish(
            "fix_loop:improvement_council",
            pass:, files: selected.size, critiques: Array(value[:feedback]).size,
            cherry_picks: Array(value[:cherry_picks]).size, anchored: findings.size
          )
          Master::Trace::Dmesg.status(
            "fix0",
            "pass #{pass}, improvement council #{Master::Trace::Dmesg.counted(findings.size, "candidate")}",
          )
          findings
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.improvement_council", event_bus: @bus)
          nil
        end

        private

        HARD_REVIEW = <<~TEXT.strip
          This is the /fix hard critique, not a courtesy code review.
          Treat the files as evidence, not as the authority about themselves.
          Attack the current design before proposing repairs.

          Inspect explicitly:
          - authority: identify every source of truth, registry, generated projection, compatibility shim, and precedence rule; flag competing authorities and dead policy
          - topology: trace direct callers, callees, entrypoints, side effects, mutable state, event-bus edges, and cross-tree reach
          - scope: identify the smallest correct write boundary and anything the change could accidentally touch outside it
          - bypasses: look for environment flags, fast paths, fallback modes, skip switches, rescue branches, defaults, or aliases that can silently weaken a safety property
          - evidence: distinguish measured behavior from comments, prompts, assumptions, and model opinion; never count "could not check" as "passed"
          - duplication: look for semantic duplicates even when filenames, classes, or registries differ; prefer one executable authority
          - generated and private material: detect stale copies, generated outputs, secrets, personal media, caches, and tracked material that should have a custody boundary
          - runtime/deployment: inspect the path from source change to real execution, including packaging, sync, restart, browser/device, network, and production gates where applicable
          - complexity: challenge new abstractions, orchestration, scoring, registries, and layers; delete machinery when an existing primitive is sufficient
          - leverage: rank concerns by proven causal reach across consumers, boundaries and contracts, not by finding count
          - scales: inspect local code first, then subsystem, tree, repository, production and human consequences when the evidence crosses those boundaries
          - unfinished work: distinguish fertile uncertainty from proven deadness; preserve a promising primitive until consumer/value evidence says it should go
          - creative identity: preserve operator-owned identity and invariants while changing one declared axis at a time
          - failure modes: identify catastrophic, silent, partial, retry, concurrency, stale-state, and rollback failures
          - verification: name the smallest deterministic test or measurement that would actually falsify each concern
          - inversion: assume the proposed repair is wrong and state what breaks, where, and when
          - completeness: never accept truncated, placeholder, or simulated work as evidence; require the smallest falsifiable proof

          For every actionable finding, anchor it to a repository-relative file plus stable line or symbol.
          Classify claims as observed, plausible, or requiring validation.
          Do not invent defects, redesign working systems from taste, or praise the implementation.
          Prefer the smallest existing primitive that can enforce the property.
        TEXT

        def critique(files)
          return Master::Result.ok(feedback: [], issues: [], cherry_picks: [], ideas: [], mode: :general) unless hard_critique_enabled?

          briefing = hard_briefing(files)
          result = Master::Review::Council::Critique.new(
            mode: :general,
            agent: @agent,
            event_bus: @bus,
            files:,
            briefing:,
            speak_personas: true,
          ).run
          unless result.ok?
            @bus&.publish("fix_loop:hard_critique_inconclusive", files: files.size, error: result.message.to_s[0, 180])
            Master::Trace::Dmesg.status("fix0", "hard critique INCONCLUSIVE: #{result.message.to_s[0, 120]}")
          else
            value = result.value!
            @bus&.publish(
              "fix_loop:hard_critique",
              files: files.size,
              issues: Array(value[:issues]).size,
              cherry_picks: Array(value[:cherry_picks]).size,
            )
            Master::Trace::Dmesg.status(
              "fix0",
              "hard critique #{Array(value[:issues]).size} issue(s), #{Array(value[:cherry_picks]).size} repair candidate(s)",
            )
          end
          result
        rescue StandardError => e
          @bus&.publish("fix_loop:hard_critique_inconclusive", files: files.size, error: e.message[0, 180])
          Master::Trace::Dmesg.status("fix0", "hard critique INCONCLUSIVE: #{e.class}: #{e.message[0, 120]}")
          Master::Ground::Swallow.log(e, context: "fix_loop.council_round", event_bus: @bus)
          nil
        end

        def hard_critique_enabled?
          ENV.fetch("MASTER_FIX_HARD_CRITIQUE", "1") != "0"
        end

        def hard_briefing(files)
          rows = Array(files).select { |path| File.file?(path) }.first(FILES_PER_ROUND)
          relative = rows.map { |path| repo_relative(path) }.uniq
          boundary = if defined?(Master::Phoenix)
                       rows.map { |path| Master::Phoenix.scope_for(path, root: @root) }.flatten.uniq.sort
                     else
                       []
                     end
          runners = load_runners(rows)
          deterministic = [
            "target files: #{relative.join(", ")}",
            boundary.empty? ? nil : "write/runtime boundaries: #{boundary.join(", ")}",
            runners.empty? ? nil : "known test entrypoints reaching target: #{runners.join(", ")}",
            "hard critique is scoped to the files above; inspect adjacent files only when they are required to prove a dependency, authority, or runtime edge",
            @discipline.reasoning_contract(strategy: @discipline.strategy_for(files:, findings: []), files:, findings: []),
          ].compact
          [HARD_REVIEW, deterministic.join("\n")].join("\n\n")
        rescue StandardError => e
          Master::Trace::Dmesg.status("fix0", "hard critique context reduced: #{e.class}: #{e.message[0, 100]}")
          HARD_REVIEW
        end

        def load_runners(files)
          require_relative "../../../tools/runs"
          Array(files).flat_map { |path| Operator::Runs.who_runs(repo_relative(path)) }.uniq.first(12)
        rescue StandardError
          []
        end

        def improvement_findings(value, files)
          Array(value[:cherry_picks]).filter_map do |pick|
            build_improvement_finding(pick.to_s, files)
          end.uniq { |finding| [finding[:file], finding[:line], finding[:message]] }
        end

        def build_improvement_finding(pick, files)
          return if pick.strip.empty?
          return if destructive_pick?(pick) && ENV["MASTER_AUTOFIX"] != "1"

          file, line = anchor_for(pick, files)
          return unless file && line

          {
            rule: IMPROVEMENT_RULE_ID,
            kind: :improvement,
            file:,
            line:,
            severity: IMPROVEMENT_SEVERITY,
            confidence: 0.85,
            message: "Council improvement: #{pick.strip}",
            fix: "Make the smallest evidence-backed improvement at the anchored file and line. " \
                 "Preserve behavior, accessibility, semantics, responsiveness and public interfaces. " \
                 "Do not rewrite the file or introduce a new abstraction without evidence.",
          }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.improvement_finding", event_bus: @bus)
          nil
        end

        def destructive_pick?(pick)
          pick.match?(DESTRUCTIVE_IMPROVEMENT) && !pick.match?(SAFE_REMOVE_IMPROVEMENT)
        end

        def anchor_for(pick, files)
          file = file_anchor(pick, files)
          return [nil, nil] unless file

          [file, line_anchor(pick, file) || symbol_line(pick, file)]
        end

        def rotating_files(files, pass)
          rows = Array(files).select { |path| File.file?(path) }.uniq.sort
          return rows.first(FILES_PER_ROUND) if rows.empty? || rows.size <= FILES_PER_ROUND

          offset = ((pass.to_i - 1) * FILES_PER_ROUND) % rows.size
          rows.rotate(offset).first(FILES_PER_ROUND)
        end

        def file_anchor(pick, files)
          rows = Array(files).map { |path| [path, repo_relative(path), File.basename(path)] }
          paths = rows.select { |_, relative, _| pick.include?(relative) }
          return paths.first[0] if paths.size == 1

          basenames = rows.select do |_, _, basename|
            pick.match?(%r{(?<![\w.-])#{Regexp.escape(basename)}(?![\w.-])})
          end
          basenames.first[0] if basenames.size == 1
        end

        def line_anchor(pick, file)
          match = pick.match(LINE_RE)
          if match
            line = match[1].to_i
            return line if line.positive?
          end

          basename = File.basename(file)
          relative = repo_relative(file)
          path_match = [relative, basename].find { |path| pick.include?("#{path}:") }
          return unless path_match

          path_match_match = pick.match(/#{Regexp.escape(path_match)}:(\d+)\b/)
          line = path_match_match&.captures&.first.to_i
          line.positive? ? line : nil
        end

        def symbol_line(pick, file)
          match = pick.match(SYMBOL_RE)
          return unless match

          kind, name = match.captures
          File.foreach(file, encoding: "UTF-8").with_index(1) do |line, number|
            return number if line.match?(/\b#{Regexp.escape(kind)}\s+#{Regexp.escape(name)}\b/)
          end
          nil
        end

        def repo_relative(path)
          base = File.basename(File.expand_path(@root)) == "MASTER" ? File.expand_path("..", @root) : @root
          File.expand_path(path).delete_prefix("#{File.expand_path(base)}/")
        end

        def publish(value, pass:, files:)
          picks = Array(value[:cherry_picks]).size
          @bus&.publish("fix_loop:council", pass:, files: files.size,
                                            critiques: Array(value[:feedback]).size, cherry_picks: picks)
          Master::Trace::Dmesg.status("fix0",
                                      "pass #{pass}, council picked #{Master::Trace::Dmesg.counted(picks, "repair")}")
        end
      end
    end
  end
end
