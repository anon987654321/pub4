# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      class PassRunner
        # The LLM-driven fix stage: orders runnable rules by dependency level,
        # dispatches each rule group (in parallel when the group's violations
        # touch disjoint files), and tracks circuit/deadline state — separate
        # concern from the deterministic FastStage pipeline.
        module LlmStage
          private

          def llm_pass(violations:, files:, pass:, deadline: nil, council: nil)
            law_violations = violations.group_by { |v| v[:law].to_s }
            ordered = @law_order.ordered(violation_counts: @law_violation_counts)
            runnable = ordered.select { |law| law_violations.key?(law.id.to_s) }
            runnable += semantic_law_adapters(law_violations, ordered)
            if runnable.empty? && law_violations.any?
              Master::Trace::Dmesg.status(
                "fix0",
                "no registered law fixes #{law_violations.keys.first(5).join(", ")}; " \
                "registered: #{ordered.map { |law| law.id.to_s }.first(5).join(", ")}",
              )
            end
            fixed = run_dependency_levels(runnable, files:, pass:, law_violations:, deadline:, council:)
            publish_llm_pass_status(pass:, deadline:)
            fixed
          end

          def run_wishlist_stage(findings, pass:, files:, deadline:, run_id:)
            return 0 if findings.empty? || Time.now >= deadline

            fixed = 0
            findings.each do |finding|
              break if Time.now >= deadline

              law = Wishlist::Law.new(Wishlist::LAW_ID)
              proposal = finding[:wishlist_proposal] || {}
              loop = LawLoop.new(
                law:, agent: @agent, scanner: @scanner, root: @root, bus: @bus,
                learnings: @learnings, committer: @committer, stage_commit: true,
                visual_custody: @visual_pass&.custody,
              )
              loop.injected_preamble = [
                @preamble,
                "AUTOMATIC WISHLIST PROPOSAL",
                "Proposal: #{proposal["uid"]}",
                "Evidence is binding context; re-read the live anchor before changing it.",
                "Implement the smallest change that satisfies the proposal and preserves unrelated behavior.",
              ].join("\n\n")
              result = loop.run_once([finding[:file]], external_violations: [finding])
              applied = result[:fixed].to_i
              fixed += applied
              @wishlist&.mark_attempt(
                proposal_id: finding[:wishlist_id],
                fixed: applied,
                status: result[:status],
                message: result[:breakdown].to_h.keys.join(", "),
                run_id: run_id || proposal["generated_by_run"],
              )
              @bus&.publish(
                "fix_loop:wishlist_attempt",
                pass:,
                id: finding[:wishlist_id],
                status: result[:status],
                fixed: applied,
              )
            end
            Master::Trace::Dmesg.status("fix0", "pass #{pass}, wishlist #{fixed}/#{findings.size} applied") if findings.any?
            fixed
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "fix_loop.wishlist_stage", event_bus: @bus)
            0
          end

          def run_dependency_levels(runnable, files:, pass:, law_violations:, deadline:, council: nil)
            fixed = 0
            breakdown = Hash.new(0)
            @law_order.dependency_levels(runnable).each do |group|
              break if deadline && Time.now >= deadline
              break if circuit_open?
              results = run_law_group(group:, files:, pass:, law_violations:, council:)
              fixed += tally_law_results(results, breakdown:, pass:)
              @human_decision_required ||= results.any? { |_law, result| result[:status] == :human_decision }
            end
            report_skip_breakdown(breakdown, pass:)
            fixed
          end

          # A rule that reported no breakdown of its own counts once under its
          # status, so every rule contributes exactly one row either way.
          def tally_law_results(results, breakdown:, pass:)
            results.sum do |law, result|
              @law_violation_counts[law.id] += result[:fixed].to_i
              tallied = result[:breakdown]
              if tallied.nil? || tallied.empty?
                breakdown[result[:status] || :unknown] += 1
              else
                tallied.each { |outcome, count| breakdown[outcome] += count }
              end
              @bus&.publish("fix_loop:law_result", pass:, law: law.id, **result)
              result[:fixed].to_i
            end
          end

          def report_skip_breakdown(breakdown, pass:)
            return if breakdown.empty?

            parts = breakdown.map { |status, count| "#{count} #{status}" }.join(", ")
            Master::Trace::Dmesg.status("fix0", "pass #{pass}, #{parts}")
            @bus&.publish("fix_loop:skip_breakdown", pass:, **breakdown.transform_keys(&:to_sym))
          end

          def publish_llm_pass_status(pass:, deadline:)
            if deadline && Time.now >= deadline
              @bus&.publish("fix_loop:pass_timeout", pass:)
            elsif circuit_open?
              @bus&.publish("fix_loop:llm_skipped", pass:, reason: "circuit_open", open: open_breakers)
            end
          end

          def run_law_group(group:, files:, pass:, law_violations:, council: nil)
            unless disjoint_law_files?(group, law_violations)
              return group.map do |law|
                [law, run_law_once(law, files, pass, council:,
                                     external_violations: law_violations[law.id.to_s])]
              end
            end

            group.map do |law|
              Thread.new do
                [law, run_law_once(law, files, pass, council:,
                                     external_violations: law_violations[law.id.to_s])]
              end
            end.map(&:value)
          end

          # What the council picked this pass, as repairs to weigh rather than
          # instructions to copy. The fixer still answers to the rule and to
          # PRESERVE_FIRST: a stronger proposal is not automatically a larger
          # change, and a proposal that breaks the rule it addresses is no repair.
          def council_preamble(council)
            picks = Array(council && council[:cherry_picks]).map { |pick| "- #{pick}" }
            return if picks.empty?

            "COUNCIL\nThe council read these files and argued about them. These are the repairs " \
              "it judged strongest. Prefer the one that satisfies the law with the smallest " \
              "change that preserves what the code means; ignore any that does neither.\n#{picks.join("\n")}"
          end

          SemanticFixLaw = Data.define(:id, :severity, :law) do
            def semantic? = true
            def practice = nil
            def ask = law.ask
            def fix = law.fix
            def contract_entry = law.contract_entry
          end

          def semantic_law_adapters(law_violations, ordered)
            known = ordered.map { |law| law.id.to_s }.to_set
            require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
            ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?
            law_violations.keys.reject { |id| known.include?(id.to_s) }.filter_map do |id|
              law = ::Law.definitions.find { |definition| definition.id.to_s == id.to_s }
              next unless law&.semantic?
              SemanticFixLaw.new(id: id.to_s, severity: law.severity, law:)
            end
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "fix_loop.semantic_law_adapters", event_bus: @bus, severity: :load_bearing)
            raise "semantic law adapter load failed: #{e.class}: #{e.message}"
          end

          def run_law_once(law, files, pass, council: nil, external_violations: nil)
            rl = LawLoop.new(law:, agent: @agent, scanner: @scanner, root: @root, bus: @bus,
                              learnings: @learnings, committer: @committer,
                              visual_custody: @visual_pass&.custody)
            rl.injected_preamble = [@preamble, council_preamble(council)].compact.join("\n\n")
            @bus&.publish("fix_loop:tier2_quality_route", pass:, law: law.id) if @law_order.tier2?(law.id)
            normalized = Array(external_violations).map do |violation|
              file = violation[:file].to_s
              absolute = file.start_with?("/") ? file : File.expand_path(file, @root)
              Violation.from_finding(violation.to_h, file: absolute)
            end
            rl.run_once(files, external_violations: normalized.empty? ? nil : normalized)
          end

          def disjoint_law_files?(laws, law_violations)
            seen = Set.new
            laws.all? do |law|
              files = Array(law_violations[law.id.to_s]).map { |v| v[:file].to_s }.uniq
              overlap = files.any? { |f| seen.include?(f) }
              files.each { |f| seen << f }
              !overlap
            end
          end
        end
      end
    end
  end
end
