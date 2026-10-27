# frozen_string_literal: true

require_relative "../../law/definition"

module Master
  module Fix
    # Runs every active law through four independent assessment streams on each
    # declared surface. Missing assessors are INCONCLUSIVE, never clean.
    #
    # This is deliberately adapter-driven: language parsers, path inventories,
    # cross-file analyzers, browser probes and model reviewers each keep their
    # own evidence contract while sharing one convergence and coverage ledger.
    class FourStreamAssessment
      STREAMS = %i[
        lexical_violations
        lexical_opportunities
        semantic_violations
        semantic_opportunities
      ].freeze

      SURFACES = ::Law::ASSESSMENT_SURFACES

      FINDING_STATES = %i[violation_found opportunity_found].freeze

      STATES = %i[
        assessed_clean violation_found opportunity_found not_applicable inconclusive
      ].freeze

      # Machine-readable expectations only. A declared contract is not runtime
      # proof; callers must supply assessors and emit evidence for each cell.
      def self.contract
        {
          version: 1,
          streams: STREAMS.map(&:to_s),
          surfaces: SURFACES.map(&:to_s),
          statuses: (STATES + [:pending]).map(&:to_s),
          clean_passes_required: 2,
          completion_rule: "all applicable law × stream × surface cells have two consecutive evidence-backed clean readings after the last mutation",
          runtime_status: "contract_only_not_measurement",
        }
      end

      Result = Data.define(
        :law, :stream, :surface, :status, :iteration, :generation,
        :reason, :evidence, :findings, :repair
      )

      attr_reader :laws, :surfaces, :history, :clean_passes, :max_iterations,
                  :generation, :last_mutation_iteration

      def initialize(laws:, surfaces: SURFACES, clean_passes: 2, max_iterations: 15)
        @laws = Array(laws).map { |law| law_id(law) }.uniq.freeze
        @surfaces = Array(surfaces).map(&:to_sym).uniq.freeze
        @clean_passes = Integer(clean_passes)
        @max_iterations = Integer(max_iterations)
        raise ArgumentError, "law population is empty" if @laws.empty?
        raise ArgumentError, "surface population is empty" if @surfaces.empty?
        raise ArgumentError, "clean_passes must be positive" unless @clean_passes.positive?
        raise ArgumentError, "max_iterations must be positive" unless @max_iterations.positive?
        unknown_surfaces = @surfaces - SURFACES
        raise ArgumentError, "unknown surfaces: #{unknown_surfaces.join(', ')}" unless unknown_surfaces.empty?

        @history = Hash.new { |hash, key| hash[key] = [] }
        @generation = 0
        @last_mutation_iteration = 0
      end

      # assessors may be keyed by [stream, surface] or by stream. Each assessor
      # returns { status:, reason:, evidence:, findings: }. The repairer receives
      # the same context and returns { changed: true }. Every global round visits
      # every cell. Any mutation advances the generation and invalidates prior
      # clean readings everywhere; DONE requires two mutation-free clean rounds.
      def run(assessors:, repairer: nil)
        1.upto(max_iterations) do |iteration|
          cells.each do |law, stream, surface|
            assess_cell(law:, stream:, surface:, iteration:, assessors:, repairer:)
          end
          break if clean?
        end

        finalize_open_cells
        report
      end

      def record(law:, stream:, surface:, status:, iteration:, generation: @generation,
                 reason: nil, evidence: [], findings: [], repair: nil)
        key = cell_key(law, stream, surface)
        raise ArgumentError, "unknown law: #{key[0]}" unless laws.include?(key[0])
        raise ArgumentError, "unknown stream: #{key[1]}" unless STREAMS.include?(key[1])
        raise ArgumentError, "unknown surface: #{key[2]}" unless surfaces.include?(key[2])

        state = status.to_sym
        raise ArgumentError, "unknown assessment state: #{state}" unless STATES.include?(state)
        detail = reason.to_s.strip
        raise ArgumentError, "#{state} requires a reason" if %i[not_applicable inconclusive].include?(state) && detail.empty?

        evidence_rows = evidence.nil? ? [] : Array(evidence)
        finding_rows = findings.nil? ? [] : Array(findings)
        if state == :assessed_clean && evidence_rows.empty?
          raise ArgumentError, "assessed_clean requires evidence naming what was examined"
        end
        if FINDING_STATES.include?(state) && evidence_rows.empty? && finding_rows.empty?
          raise ArgumentError, "#{state} requires evidence or a finding"
        end

        iteration = Integer(iteration)
        generation = Integer(generation)
        raise ArgumentError, "iteration must be positive" unless iteration.positive?
        raise ArgumentError, "generation cannot be negative" if generation.negative?
        previous = history[key].last
        if previous && iteration <= previous.iteration
          raise ArgumentError, "iteration must advance for #{key.join("/")}"
        end

        row = Result.new(
          law: key[0], stream: key[1], surface: key[2], status: state,
          iteration:, generation:, reason: detail.empty? ? nil : detail,
          evidence: evidence_rows.freeze, findings: finding_rows.freeze, repair:
        )
        history[key] << row
        row
      end

      # Called when the owning /fix plan detects a source, scope, Law, authority,
      # toolchain, exclusion or adapter mutation. Old clean readings remain auditable
      # but cannot satisfy the new generation's clean streak.
      def invalidate!(iteration:, reason:)
        iteration = Integer(iteration)
        raise ArgumentError, "mutation iteration cannot be negative" if iteration.negative?

        @generation += 1
        @last_mutation_iteration = [@last_mutation_iteration, iteration].max
        @invalidations ||= []
        @invalidations << {
          iteration:,
          generation: @generation,
          reason: reason.to_s[0, 240],
        }.freeze
        @generation
      end

      # Small summary for the terminal event. Full findings remain available via
      # #report; callers need not serialize every unassessed cell to know coverage.
      def summary
        keys = cells
        latest = keys.map { |key| [key, history[key].last] }
        by_stream = STREAMS.to_h do |stream|
          rows = latest.select { |key, _row| key[1] == stream }.map(&:last)
          counts = (STATES + [:pending]).to_h do |state|
            [state, rows.count { |row| row ? row.status == state : state == :pending }]
          end
          [stream, { cells: rows.size, states: counts }]
        end
        {
          laws: laws.size,
          generation:,
          last_mutation_iteration:,
          clean_passes_required: clean_passes,
          expected_cells: keys.size,
          recorded_cells: latest.count { |_key, row| !row.nil? },
          unassessed_cells: latest.count { |_key, row| row.nil? },
          inconclusive_cells: latest.count { |_key, row| row&.status == :inconclusive },
          finding_cells: latest.count { |_key, row| row && FINDING_STATES.include?(row.status) },
          complete: complete?,
          clean: clean?,
          streams: by_stream.transform_keys(&:to_s),
        }
      end

      # A cell is complete only after the required consecutive clean readings or
      # a reasoned not-applicable decision. Any missing work remains open.
      def complete?
        cells.all? do |key|
          latest = history[key].last
          next false unless latest

          (latest.status == :not_applicable && latest.generation == generation) ||
            (latest.status == :assessed_clean && clean_streak(key) >= clean_passes)
        end
      end

      def clean?
        complete? && cells.all? do |key|
          %i[assessed_clean not_applicable].include?(history[key].last.status)
        end
      end

      def report
        latest_by_cell = cells.to_h { |key| [key, history[key].last] }
        stream_summary = STREAMS.to_h do |stream|
          stream_cells = latest_by_cell.select { |key, _| key[1] == stream }
          counts = (STATES + [:pending]).to_h do |state|
            [state, stream_cells.count { |_, row| row ? row.status == state : state == :pending }]
          end
          [stream, { cells: stream_cells.size, states: counts }]
        end

        {
          laws: laws.size,
          generation: @generation,
          clean_passes_required: clean_passes,
          last_mutation_iteration:,
          streams: STREAMS.map(&:to_s),
          surfaces: surfaces.map(&:to_s),
          expected_cells: cells.size,
          recorded_cells: latest_by_cell.count { |_, row| !row.nil? },
          complete: complete?,
          clean: clean?,
          stream_summary:,
          open_findings: latest_by_cell.filter_map do |key, row|
            next unless row && (
              %i[violation_found opportunity_found].include?(row.status) ||
              (row.status == :inconclusive && (row.evidence.any? || row.findings.any?))
            )

            { law: key[0], stream: key[1].to_s, surface: key[2].to_s, status: row.status.to_s,
              iteration: row.iteration, reason: row.reason, evidence: row.evidence,
              findings: row.findings }
          end,
          inconclusive: latest_by_cell.filter_map do |key, row|
            next unless row&.status == :inconclusive

            { law: key[0], stream: key[1].to_s, surface: key[2].to_s,
              iteration: row.iteration, reason: row.reason }
          end,
          unassessed: latest_by_cell.filter_map do |key, row|
            { law: key[0], stream: key[1].to_s, surface: key[2].to_s } unless row
          end,
        }
      end

      # Durable per-cell proof, including the complete transition history. The
      # compact terminal summary is intentionally separate from this audit record.
      def evidence_report
        {
          schema_version: 2,
          streams: STREAMS.map(&:to_s),
          surfaces: surfaces.map(&:to_s),
          laws:,
          summary:,
          invalidations: Array(@invalidations).map do |entry|
            {
              iteration: entry[:iteration],
              generation: entry[:generation],
              reason: entry[:reason],
            }
          end,
          cells: cells.sort_by { |key| key.map(&:to_s) }.map do |key|
            rows = history[key]
            latest = rows.last
            {
              law: key[0],
              stream: key[1].to_s,
              surface: key[2].to_s,
              status: latest ? latest.status.to_s : "pending",
              clean_streak: clean_streak(key),
              readings: rows.map { |row| reading_evidence(row) },
            }
          end,
        }
      end

      private

      def cells
        @cells ||= laws.product(STREAMS, surfaces).freeze
      end

      def reading_evidence(row)
        {
          iteration: row.iteration,
          generation: row.generation,
          status: row.status.to_s,
          reason: row.reason,
          evidence: json_safe_value(row.evidence),
          findings: json_safe_value(row.findings),
          repair: repair_evidence(row.repair),
        }
      end

      def repair_evidence(repair)
        return if repair.nil?

        if repair.is_a?(Hash)
          {
            changed: repair[:changed] == true || repair["changed"] == true,
            retryable: repair[:retryable] == true || repair["retryable"] == true,
            reason: (repair[:reason] || repair["reason"]).to_s[0, 240],
          }
        else
          { changed: repair == true }
        end
      end

      def json_safe_value(value)
        case value
        when NilClass, TrueClass, FalseClass, Numeric, String
          value
        when Symbol
          value.to_s
        when Array
          value.map { |entry| json_safe_value(entry) }
        when Hash
          value.each_with_object({}) do |(key, entry), normalized|
            normalized[key.to_s] = json_safe_value(entry)
          end
        else
          value.respond_to?(:to_h) ? json_safe_value(value.to_h) : value.to_s
        end
      end

      def cell_key(law, stream, surface)
        [law_id(law), stream.to_sym, surface.to_sym]
      end

      def law_id(law)
        value = law.respond_to?(:id) ? law.id : law
        id = value.to_s.strip
        raise ArgumentError, "law id is blank" if id.empty?

        id
      end

      # Readings collected during a round that made a repair cannot count as
      # post-repair clean passes. Require two entire later rounds.
      def clean_streak(key)
        history[key].reverse.take_while do |row|
          row.status == :assessed_clean &&
            row.generation == generation &&
            row.iteration > last_mutation_iteration
        end.size
      end

      def assessor_for(assessors, stream, surface)
        assessors[[stream, surface]] || assessors[stream] || assessors[stream.to_s]
      end

      def assess_cell(law:, stream:, surface:, iteration:, assessors:, repairer:)
        key = [law, stream, surface]
        assessor = assessor_for(assessors, stream, surface)
        unless assessor.respond_to?(:call)
          record(**record_args(key, :inconclusive, iteration,
            reason: "no assessor registered for #{stream}/#{surface}"))
          return false
        end

        outcome = normalize_outcome(assessor.call(
          law:, stream:, surface:, iteration:, prior: history[key].dup.freeze,
        ))

        unless FINDING_STATES.include?(outcome[:status])
          record(**record_args(key, outcome.fetch(:status), iteration,
            reason: outcome[:reason], evidence: outcome[:evidence],
            findings: outcome[:findings]))
          return false
        end

        unless repairer.respond_to?(:call)
          record(**record_args(key, :inconclusive, iteration,
            reason: "finding remains; no repairer is registered",
            evidence: outcome[:evidence], findings: outcome[:findings]))
          return false
        end

        repair = repairer.call(
          law:, stream:, surface:, status: outcome[:status],
          findings: Array(outcome[:findings]), evidence: Array(outcome[:evidence]), iteration:
        )
        changed = repair == true || (repair.respond_to?(:[]) && repair[:changed] == true)
        retryable = repair.respond_to?(:[]) && repair[:retryable] == true
        unless changed
          reason = repair.respond_to?(:[]) ? repair[:reason] : nil
          reason = "repair did not change the artifact" if reason.to_s.strip.empty? && !retryable
          reason = "repair requires another iteration" if reason.to_s.strip.empty?
          record(**record_args(key, :inconclusive, iteration,
            reason:, evidence: outcome[:evidence], findings: outcome[:findings], repair:))
          return false
        end

        record(**record_args(key, outcome[:status], iteration,
          evidence: outcome[:evidence], findings: outcome[:findings], repair:))
        @generation += 1
        @last_mutation_iteration = iteration
        true
      rescue StandardError => e
        record(**record_args(key, :inconclusive, iteration,
          reason: "assessment/repair failed: #{e.class}: #{e.message}"))
        false
      end

      def finalize_open_cells
        cells.each do |key|
          latest = history[key].last
          next unless latest
          next if latest.status == :not_applicable || latest.status == :inconclusive
          next if latest.status == :assessed_clean &&
                  latest.generation == @generation && clean_streak(key) >= clean_passes

          record(**record_args(key, :inconclusive, max_iterations + 1,
            reason: "iteration limit reached before #{clean_passes} consecutive clean assessments (last state: #{latest.status})",
            generation: @generation, evidence: latest.evidence, findings: latest.findings))
        end
      end

      def normalize_outcome(value)
        raise ArgumentError, "assessor must return a Hash" unless value.is_a?(Hash)

        row = value.transform_keys(&:to_sym)
        row[:status] = row.fetch(:status).to_sym
        raise ArgumentError, "unknown assessment state: #{row[:status]}" unless STATES.include?(row[:status])

        if %i[not_applicable inconclusive].include?(row[:status]) && row[:reason].to_s.strip.empty?
          raise ArgumentError, "#{row[:status]} needs a reason"
        end
        if row[:status] == :assessed_clean && Array(row[:evidence]).compact.empty?
          raise ArgumentError, "assessed_clean needs evidence naming what was examined"
        end
        if FINDING_STATES.include?(row[:status]) &&
           Array(row[:evidence]).compact.empty? && Array(row[:findings]).compact.empty?
          raise ArgumentError, "#{row[:status]} needs evidence or a finding"
        end
        row
      end

      def record_args(key, status, iteration, **values)
        { law: key[0], stream: key[1], surface: key[2], status:, iteration:, **values }
      end
    end
  end
end
