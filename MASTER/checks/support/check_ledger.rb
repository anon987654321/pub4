# frozen_string_literal: true

require "json"
require "time"

module Deploy
  # What each check has actually been doing, run over run.
  #
  # This is the counterpart to `CheckResult#errored!`, and it is not optional
  # decoration next to it. Fail-open means a check that crashes stops blocking;
  # without a record, it also stops being noticed — it reads as a quiet line in
  # a long run and the tree it was supposed to guard goes unguarded for however
  # long nobody re-reads the output. arXiv 2607.07405 makes the same point about
  # its own suite: precision "must itself be audited", because in their four-check
  # fleet one check ran at 100% precision over 161 fires and another at 5%, and
  # nothing in the check's own output distinguished them.
  #
  # pub4 had no such record. Every check's history was whatever was still in a
  # terminal scrollback, so the two failure modes this fleet has actually hit —
  # a check that fires on every single run until people learn to skip its line
  # (the tablist warning, 2026-08), and a check that quietly measures nothing for
  # days (layout_geometry, 2026-08-03) — were both invisible in exactly the same
  # way: locally each run looked reasonable.
  #
  # What this can and cannot say. It records *outcomes*, so it yields fire rate,
  # error rate and inconclusive rate per check. It does not yield precision in the
  # paper's sense — that needs ground truth about whether each block was correct,
  # which for this fleet lives in whether someone fixed the finding or exempted
  # the rule, and nothing here can see that. Two checks that report the same
  # numbers here can still differ in precision. So the numbers are a triage
  # order, not a verdict: they say which check to go and read, not which is wrong.
  #
  # Local-only, append-only JSONL, one line per check per run. Never committed —
  # it is machine-and-operator state like `.constitutional_costs.jsonl`, and a
  # committed version would conflict on every run in a shared checkout.
  class CheckLedger
    DEFAULT_PATH = File.expand_path("../../.check_ledger.jsonl", __dir__)

    # Keep the file bounded without a cron job. Trimming on read rather than on
    # write means a run never pays for it, and the reader is the only thing that
    # cares how long the history is.
    MAX_LINES = 20_000

    attr_reader :path

    def initialize(path: nil, env: ENV)
      @path = path || env["CHECK_LEDGER"] || DEFAULT_PATH
    end

    # CHECK_LEDGER=off disables recording entirely, for runs that should leave no
    # trace (a bisect, someone else's tree).
    def enabled? = !%w[off 0 false no].include?(File.basename(@path.to_s).downcase)

    def record(check:, outcome:, run_id:, failures: 0, warnings: 0, errors: 0, duration_ms: nil, verification: nil)
      return self unless enabled?

      line = {
        at: Time.now.utc.iso8601,
        run: run_id,
        check:,
        outcome: outcome.to_s,
        failures:,
        warnings:,
        errors:,
        duration_ms:,
      }

      if verification
        raise ArgumentError, "verification receipt must be a Hash" unless verification.is_a?(Hash)

        line[:verification] = verification
      end

      File.open(@path, "a") { |f| f.puts(JSON.generate(line)) }
      self
    rescue SystemCallError => e
      # The ledger is an observer. It must never be the reason a check run dies,
      # which would make the audit mechanism itself the top source of false
      # blocks — the failure the fail-open policy exists to prevent.
      Kernel.warn "[checks] ledger write failed (#{e.class}): #{e.message}"
      self
    end

    def entries
      return [] unless File.file?(@path)

      File.readlines(@path, chomp: true).last(MAX_LINES).filter_map do |line|
        next if line.strip.empty?

        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    # One row per check, most-worth-reading first.
    #
    # Order is errored, then failed, then inconclusive, then name. A check that
    # cannot run outranks one that is merely red: the red one told you something.
    def summary(entries = self.entries)
      by_check = entries.group_by { |e| e["check"] }

      by_check.map do |check, rows|
        counts = Hash.new(0)
        rows.each { |r| counts[r["outcome"].to_s] += 1 }
        times = rows.filter_map { |r| r["duration_ms"] }

        {
          check:,
          runs: rows.size,
          passed: counts["passed"],
          failed: counts["failed"],
          inconclusive: counts["inconclusive"],
          errored: counts["errored"],
          fire_rate: rows.empty? ? 0.0 : (counts["failed"].to_f / rows.size),
          error_rate: rows.empty? ? 0.0 : (counts["errored"].to_f / rows.size),
          median_ms: median(times),
          # The last five against everything before them. A check that has started
          # taking twice as long is the failure the whole duration column is for,
          # and a median over the full history hides it by definition.
          recent_ms: median(times.last(5)),
          earlier_ms: median(times[0...-5]),
          last: rows.last["outcome"],
          last_at: rows.last["at"],
        }
      end.sort_by { |r| [-r[:errored], -r[:failed], -r[:inconclusive], r[:check].to_s] }
    end

    def median(values)
      sorted = Array(values).compact.sort
      return if sorted.empty?

      sorted[sorted.size / 2]
    end

    # A wall time a person reads without arithmetic. Anything past ninety seconds
    # is the kind of check somebody plans a coffee around, so it changes units.
    def self.duration(ms)
      return "-" if ms.nil?

      seconds = ms.to_f / 1000
      seconds < 90 ? format("%.1fs", seconds) : format("%dm%02ds", (seconds / 60).floor, (seconds % 60).round)
    end

    # The lines worth acting on, in the words of what to do about them. Returned
    # rather than printed so a check could read this too.
    def flags(rows = summary, min_runs: 5)
      rows.filter_map do |r|
        next if r[:runs] < min_runs

        if r[:error_rate] >= 0.5
          "#{r[:check]}: errored on #{r[:errored]}/#{r[:runs]} runs — it is failing open, " \
            "so whatever it guards is currently unguarded"
        elsif r[:fire_rate] >= 0.9
          "#{r[:check]}: failed on #{r[:failed]}/#{r[:runs]} runs — either a standing unfixed " \
            "finding or a line people have learned to skip; read it or retire it"
        elsif r[:inconclusive] == r[:runs]
          "#{r[:check]}: measured nothing on all #{r[:runs]} runs — its preconditions are never met here"
        elsif doubled?(r)
          "#{r[:check]}: #{self.class.duration(r[:earlier_ms])} -> #{self.class.duration(r[:recent_ms])} " \
            "over the last five runs — a check that doubles becomes a check nobody runs"
        end
      end
    end

    def render(io = $stdout)
      rows = summary
      if rows.empty?
        io.puts "[checks] ledger #{display_path} is empty — no runs recorded yet"
        return
      end

      io.puts "[checks] ledger #{display_path} — #{rows.sum { |r| r[:runs] }} check-runs across #{rows.size} checks"
      io.puts format("  %-24s %5s %5s %5s %5s %5s %9s  %s",
                     "check", "runs", "pass", "fail", "inc", "err", "median", "last")

      rows.each do |r|
        io.puts format(
          "  %-24s %5d %5d %5d %5d %5d %9s  %s",
          r[:check], r[:runs], r[:passed], r[:failed], r[:inconclusive], r[:errored],
          self.class.duration(r[:median_ms]), r[:last]
        )
      end

      notes = flags(rows)
      return if notes.empty?

      io.puts
      io.puts "Worth reading:"
      notes.each { |n| io.puts "  - #{n}" }
    end

    private

    # Twice as slow, with enough runs on both sides of the line for the
    # comparison to mean anything and enough absolute time for it to matter. A
    # 40ms check that becomes an 80ms check is noise, not a regression.
    def doubled?(row)
      row[:recent_ms] && row[:earlier_ms] &&
        row[:earlier_ms] >= 1_000 && row[:recent_ms] >= row[:earlier_ms] * 2
    end

    def display_path = @path.sub("#{File.expand_path('../..', __dir__)}/", "")
  end
end
