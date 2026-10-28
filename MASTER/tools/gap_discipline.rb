# frozen_string_literal: true

require "yaml"

module Deploy
  # The gap discipline: absence has a paper trail or it does not exist.
  #
  # Scanners see violations of what exists. Nothing else in the tree sees what
  # is missing. data/gaps.yml is the registry of missing things;
  # data/ideations/*.yml are the ideation records that turn a gap into
  # candidates, attack every candidate, and cherry-pick a winner with the
  # losers' reasons kept; convergence.yml carries the winner as a workstream.
  # This check is the seam between those files: it fails loudly when the
  # chain is broken — a pick without a kept verdict, a gap with fewer
  # candidates than a real choice needs, a "picked" ledger row with no
  # workstream, a workstream name that exists nowhere.
  #
  # Per-gap floor is Council::Critique::CherryPick::PER_ISSUE_LIMIT (3):
  # three materially distinct options leave a gap with a real choice. The
  # per-pass floor exists so a "pass" that covered one gap with three rows
  # cannot claim to have ideated.
  module GapDiscipline
    MIN_CANDIDATES_PER_GAP = 3
    MIN_CANDIDATES_PER_PASS = 10
    KINDS = %w[logic content knowledge ux].freeze
    STATES = %w[open ideating picked satisfied rejected blocked].freeze
    AXES = %w[spec hyperlocal synergy cost laws_delta reversibility].freeze
    VERDICTS = %w[keep reject].freeze

    module_function

    def run(root:, io: $stdout)
      errors = []
      by_id, rows = read_ledger(root, errors)
      winners, pass_total = read_records(root, errors)

      if pass_total.positive? && pass_total < MIN_CANDIDATES_PER_PASS
        errors << "ideation pass: #{pass_total} candidates across all records, needs #{MIN_CANDIDATES_PER_PASS}"
      end

      by_id.each_value do |row|
        id = row["id"]
        next unless row["status"] == "picked"

        errors << "ledger #{id}: status picked but no ideation record picks it" unless winners.key?(id)
        errors << "ledger #{id}: status picked without a workstream row" if row["workstream"].nil?
      end

      ws_ids = workstream_ids(root, errors)
      by_id.each_value do |row|
        ws = row["workstream"]
        next if ws.nil? || ws_ids.nil? || ws_ids.include?(ws)

        errors << "ledger #{row['id']}: workstream #{ws} not found in convergence.yml"
      end

      if errors.empty?
        io.puts "gap discipline: CLEAN — #{by_id.size} gaps, #{pass_total} candidates, #{winners.size} picks reconciled"
        true
      else
        errors.each { |error| io.puts "gap discipline: #{error}" }
        false
      end
    end

    def read_ledger(root, errors)
      ledger = load(File.join(root, "data", "gaps.yml"), errors) || {}
      by_id = {}
      Array(ledger["gaps"]).each do |row|
        id = row["id"]
        if id.nil? || by_id.key?(id)
          errors << "ledger: duplicate or missing gap id #{id.inspect}"
          next
        end

        by_id[id] = row
        errors << "ledger #{id}: unknown state #{row['status'].inspect}" unless row["status"].nil? || STATES.include?(row["status"])
        errors << "ledger #{id}: unknown kind #{row['kind'].inspect}" unless KINDS.include?(row["kind"])
      end
      [ by_id, Array(ledger["gaps"]) ]
    end

    def read_records(root, errors)
      candidates_by_id = {}
      crits = {}
      winners = {}
      pass_total = 0

      Dir[File.join(root, "data", "ideations", "*.yml")].sort.each do |path|
        rel = path.delete_prefix("#{root}/")
        record = load(path, errors) || next
        pass_total += read_one_record(record, rel, candidates_by_id, crits, winners, errors)
      end

      [ winners, pass_total ]
    end

    def read_one_record(record, rel, candidates_by_id, _crits, winners, errors)
      candidates = Array(record["candidates"])
      verdicts = {}
      counted = Hash.new(0)

      Array(record["critique"]).each do |entry|
        cid = entry["candidate"]
        errors << "#{rel}: duplicate critique for #{cid.inspect}" if verdicts.key?(cid)
        verdicts[cid] = entry
        errors << "#{rel} #{cid}: unknown verdict #{entry['verdict'].inspect}" unless VERDICTS.include?(entry["verdict"])
      end

      candidates.each do |cand|
        cid = cand["id"]
        if cid.nil? || candidates_by_id.key?(cid)
          errors << "#{rel}: duplicate or missing candidate id #{cid.inspect}"
          next
        end

        candidates_by_id[cid] = cand
        AXES.each { |axis| errors << "#{rel} #{cid}: missing axis #{axis}" if cand[axis].nil? }
        errors << "#{rel} #{cid}: no critique entry" unless verdicts.key?(cid)
        counted[cand["gap"]] += 1 if cand["gap"]
      end

      Array(record["gaps"]).each do |gap|
        next unless counted[gap] < MIN_CANDIDATES_PER_GAP

        errors << "#{rel}: gap #{gap} has #{counted[gap]} candidates, needs #{MIN_CANDIDATES_PER_GAP}"
      end

      read_picks(record, rel, candidates_by_id, verdicts, winners, errors)
      candidates.size
    end

    def read_picks(record, rel, candidates_by_id, verdicts, winners, errors)
      Array(record["picks"]).each do |pick|
        gap = pick["gap"]
        winner = pick["winner"]
        cand = candidates_by_id[winner]
        if cand.nil? || cand["gap"] != gap
          errors << "#{rel}: pick for #{gap} names winner #{winner.inspect} who is not a candidate of that gap"
          next
        end

        entry = verdicts[winner]
        if entry.nil? || entry["verdict"] != "keep"
          errors << "#{rel}: pick for #{gap} names #{winner} whom critique did not keep"
          next
        end

        if winners.key?(gap)
          errors << "#{rel}: second pick for gap #{gap}"
          next
        end

        winners[gap] = [ rel, winner ]
      end
    end

    def workstream_ids(root, errors)
      config = load(File.join(root, "convergence.yml"), errors) || {}
      Array(config["workstreams"]).filter_map { |row| row["id"] }
    end

    def load(path, errors)
      YAML.safe_load_file(path, aliases: false)
    rescue StandardError => e
      errors << "#{path}: unparseable (#{e.class})"
      nil
    end
  end
end
