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
        IMPROVEMENT_SEVERITY = :warning
        DESTRUCTIVE_IMPROVEMENT = /\b(?:delete|remove|drop|erase|discard)\b/i.freeze
        LINE_RE = /\b(?:line|ln)\s*#?\s*(\d+)\b|:(\d+)\b/i.freeze
        SYMBOL_RE = /\b(class|module|def)\s+([A-Za-z_]\w*[!?=]?)/i.freeze

        def initialize(agent:, root:, bus: nil)
          @agent = agent
          @root = root
          @bus = bus
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
        # let RuleLoop apply the repair under the normal verification gates.
        # Only the first clean streak pass asks, so the next pass can confirm the
        # result without paying for the same exploratory review twice.
        def improve(files:, pass:, deadline:)
          return if @agent.nil? || files.empty? || Time.now >= deadline

          selected = rotating_files(files, pass)
          result = critique(selected)
          return unless result&.ok?

          value = result.value!
          findings = improvement_findings(value, selected)
          @bus&.publish(
            "fix_loop:improvement_council",
            pass:, files: selected.size, critiques: Array(value[:feedback]).size,
            cherry_picks: Array(value[:cherry_picks]).size, anchored: findings.size,
          )
          Master::Trace::Dmesg.status(
            "fix0",
            "pass #{pass}, improvement council #{Master::Trace::Dmesg.counted(findings.size, "candidate")}",
          ) if findings.any?
          findings
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.improvement_council", event_bus: @bus)
          nil
        end

        private

        def critique(files)
          Master::Review::Council::Critique.new(mode: :general, agent: @agent, event_bus: @bus, files:).run
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.council_round", event_bus: @bus)
          nil
        end

        def improvement_findings(value, files)
          Array(value[:cherry_picks]).filter_map do |pick|
            build_improvement_finding(pick.to_s, files)
          end.uniq { |finding| [finding[:file], finding[:line], finding[:message]] }
        end

        def build_improvement_finding(pick, files)
          return if pick.strip.empty?
          return if destructive_pick?(pick) && ENV["MASTER_AUTOFIX"] != "1"

          file = file_anchor(pick, files)
          return unless file

          line = line_anchor(pick) || symbol_line(pick, file)
          return unless line

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
          pick.match?(DESTRUCTIVE_IMPROVEMENT)
        end

        def rotating_files(files, pass)
          rows = Array(files).select { |path| File.file?(path) }.uniq.sort
          return rows.first(FILES_PER_ROUND) if rows.empty? || rows.size <= FILES_PER_ROUND

          offset = ((pass.to_i - 1) * FILES_PER_ROUND) % rows.size
          rows.rotate(offset).first(FILES_PER_ROUND)
        end

        def file_anchor(pick, files)
          rows = Array(files).map { |path| [path, repo_relative(path), File.basename(path)] }
          exact = rows.select do |_, relative, basename|
            pick.include?(relative) || pick.match?(%r{(?<![\w.-])#{Regexp.escape(basename)}(?![\w.-])})
          end
          exact.sort_by { |_, relative, basename| pick.include?(relative) ? 0 : (basename ? 1 : 2) }.first&.first
        end

        def line_anchor(pick)
          match = pick.match(LINE_RE)
          (match && (match[1] || match[2]).to_i).then { |line| line.positive? ? line : nil }
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
          repo = File.expand_path("..", @root)
          File.expand_path(path).delete_prefix("#{repo}/")
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
