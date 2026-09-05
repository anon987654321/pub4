# frozen_string_literal: true

require "open3"
require "rbconfig"

module Pub4
  # Every gate in the repo, in one order, fixing as it goes.
  #
  # The pieces all existed and nothing ran them together: `bin/gate` held the
  # scanner chain, `RAILS/gates/runner.rb --all` the app gates, `bin/check` the
  # suites, `bin/pub4 measure` the ratchets, `tools/sprawl_census.rb` the shape of
  # the tree. Five invocations, no run covering the repo, so "is the tree
  # conformant" answered for whichever quarter the last session measured.
  #
  # Three properties the pieces lack apart — why this orchestrates, not aliases:
  #
  #   Attribution. Autofix has broken dilla, postpro and MASTER's own chat path,
  #   so each stage is bracketed by a snapshot of the working tree and reports
  #   the files IT changed, under its own name, rather than leaving one diff for
  #   the next session to bisect.
  #
  #   Foreign dirt. This checkout is shared, so whatever is already modified at
  #   the start is recorded, excluded from every stage's attribution, and printed
  #   at the top before anyone commits it by reflex.
  #
  #   Honest tiers. A stage that measured nothing is neither a pass nor a
  #   failure: it reports as skipped and the run exits 3, the third state
  #   RAILS/gates/runner.rb already spells for a precondition it never met.
  module GateChain
    ROOT = File.expand_path("../../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")
    RUBY = RbConfig.ruby

    # Paths nothing writes by hand. `bin/gate` has said in a comment for months
    # that scanner.rb skips `cache` but not `.cache`, so /fix descends into
    # STUDIO's generated lora/**/.cache/** copies — a warning with no reader.
    # This is the reader: a rewritten generated file is named, and fails the run.
    GENERATED = %r{/\.cache/|/node_modules/|/public/assets/|/app/assets/builds/|\.lock\z}

    # The panel argues until the late idea arrives and hands back a long list, and
    # an unbounded queue of unattended edits on a shared checkout is the failure
    # this file makes attributable. So the queue has a floor under it.
    PICK_BUDGET = Integer(ENV.fetch("PUB4_GATE_COUNCIL_PICKS", "5"))

    # ok / failed / skipped; skipped is the one that matters.
    Result = Struct.new(:stage, :state, :summary, :changed, keyword_init: true)

    # `mutates` is a claim, and the attribution below tests it: a stage declared
    # non-mutating that changes a file fails the run.
    Stage = Struct.new(:name, :purpose, :mutates, :run, keyword_init: true)

    module_function

    # The ladder. Order is not taste: the deterministic fixers run first so
    # everything after measures the fixed tree; the ratchets run after the suites
    # because a fix moves the numbers; sprawl runs after the ratchets because it
    # only locks in a fall that already happened; and the council runs last
    # because it is the only stage that costs money and the only one that
    # currently cannot answer — a tier with no answer must not stand between the
    # rest of the ladder and its verdict.
    def stages(scan_only:)
      [
        Stage.new(name: "lexical", purpose: "law/ and the scan registry over all four trees, autofixing",
                  mutates: !scan_only, run: -> { gate("--lexical-only", scan_only:) }),
        Stage.new(name: "source", purpose: "every RAILS gate, source and rendered, fix + remeasure",
                  mutates: !scan_only, run: -> { rails_gates(scan_only:) }),
        Stage.new(name: "suites", purpose: "MASTER, the three apps, the RAILS contracts, OPENBSD, STUDIO",
                  mutates: false, run: -> { suites }),
        Stage.new(name: "ratchets", purpose: "every recorded ceiling, current beside it", mutates: false,
                  run: -> { capture(RUBY, File.join(MASTER, "bin", "pub4"), "measure") }),
        Stage.new(name: "sprawl", purpose: "lone dirs, stutter, vague names, duplicate files",
                  mutates: !scan_only, run: -> { sprawl(scan_only:) }),
        Stage.new(name: "council", purpose: "/critique and /review, then the panel's picks back through the runtime",
                  mutates: council_fix?(scan_only:), run: -> { council(scan_only:) }),
      ]
    end

    # /critique IS the council: dispatch_critique hands the path to
    # Review::Council::Critique, which runs the persona panel, the adversarial
    # round and the cherry-pick. A second one here is a second debate.
    def council(scan_only:)
      ok, body, exitstatus = gate("--semantic-only", scan_only:)
      # Exit 3 is the panel saying it reached nobody — today, four personas
      # against a provider out of credit. Straight through, so the summary
      # reports the tier as skipped and the run refuses to call itself clean.
      return [ok, body, exitstatus] unless ok

      picks = cherry_picks
      return [true, body + ["council: no cherry-picks to act on"], 0] if picks.empty?
      return act_on(picks, body) if council_fix?(scan_only:)

      noted = picks.map { |pick| "council: pick — #{pick}" }
      [true, body + noted + ["council: #{picks.size} pick(s) recorded, none acted on here"], 0]
    end

    # A pick is a sentence, not a diff, so it goes to the instruction surface.
    # `bin/master "<pick>"` is the runtime with the whole repo in reach; /fix
    # takes a path, applies deterministic transforms, and cannot read an argument.
    def act_on(picks, body)
      acted = picks.first(PICK_BUDGET).map do |pick|
        ok, out, = capture(RUBY, File.join(MASTER, "bin", "master"), pick)
        ["#{ok ? "implemented" : "REFUSED"}: #{pick}", out.last(3)]
      end
      failed = acted.count { |line, _| line.start_with?("REFUSED") }
      lines = body + acted.flat_map { |line, out| ["council: #{line}", *out.map { |o| "council|   #{o}" }] }
      lines << "council: #{acted.size} of #{picks.size} pick(s) acted on, #{failed} refused"
      [failed.zero?, lines, failed.zero? ? 0 : 1]
    end

    # Harvest writes every deliberation to .master/critiques/<mode>_latest.md
    # rather than losing it to scrollback. That file is this stage's input.
    def cherry_picks = picks_in(File.join(MASTER, ".master", "critiques"))

    def picks_in(dir)
      latest = Dir.glob(File.join(dir, "*_latest.md")).max_by { |file| File.mtime(file) }
      return [] unless latest

      section = File.read(latest).split("## cherry-picked").last.to_s
      section.lines.filter_map { |line| line.strip[/\A-\s+(.+)\z/, 1] }.reject(&:empty?)
    rescue StandardError => e
      warn "council: the harvest under #{dir} did not read — #{e.class}: #{e.message}"
      []
    end

    # Never in scan-only: that mode's promise is a shared checkout untouched.
    # PUB4_GATE_COUNCIL_FIX=0 turns it off in full-fix too, for a run where the
    # panel argues and nothing moves.
    def council_fix?(scan_only:)
      !scan_only && ENV.fetch("PUB4_GATE_COUNCIL_FIX", "1") != "0"
    end

    def gate(tier, scan_only:)
      capture(RUBY, File.join(MASTER, "bin", "gate"), tier, *(scan_only ? ["--scan-only"] : []))
    end

    # GATE_AUTOFIX defaults to on; naming it keeps scan-only honest either way.
    def rails_gates(scan_only:)
      capture(RUBY, "gates/runner.rb", "--all", chdir: File.join(ROOT, "RAILS"),
                                                env: { "GATE_AUTOFIX" => scan_only ? "0" : "1" })
    end

    OPENBSD_SUITE = %(Dir["test/test_*.rb"].sort.each { |f| system(RbConfig.ruby, f) || abort(f) })

    # Whole suites, not the ones the diff touches: a green over hand-picked tests
    # is unmeasured. This is `bin/pub4 test`'s mapping with every path in it.
    def suite_jobs
      [
        ["MASTER", [RUBY, File.join(MASTER, "bin", "check"), "--profile=ci"], MASTER, {}],
        ["RAILS contracts", [RUBY, "test/run_all.rb"], File.join(ROOT, "RAILS"), {}],
        *%w[brgen amber bsdports].map do |app|
          ["#{app} suite", %w[rbenv exec bundle exec bin/rails test],
           File.join(ROOT, "RAILS", app), { "RBENV_VERSION" => "3.4.9" }]
        end,
        ["OPENBSD", [RUBY, "-e", OPENBSD_SUITE], File.join(ROOT, "OPENBSD"), {}],
        ["STUDIO", %w[bundle exec rake studio], MASTER, {}],
      ]
    end

    def suites
      results = suite_jobs.map do |name, cmd, dir, env|
        ok, out = capture(*cmd, chdir: dir, env: env)
        [name, ok, out]
      end
      failed = results.reject { |_, ok, _| ok }
      body = results.map { |name, ok, _| "#{name}: #{ok ? "ok" : "FAIL"}" }
      body += failed.flat_map { |name, _, out| out.last(12).map { |line| "#{name}| #{line}" } }
      body << "suites: #{results.size - failed.size}/#{results.size} green"
      [failed.empty?, body, failed.empty? ? 0 : 1]
    end

    # Reduction, not rearrangement. The census counts a directory bought for one
    # file, a name repeating its parent, a name that says nothing; --ratchet
    # records a fall so the ground cannot be given back. Moving a file to drop one
    # of those is a namespace judgement and not a tool's to make.
    def sprawl(scan_only:)
      census = [RUBY, File.join(MASTER, "tools", "sprawl_census.rb")]
      census << "--ratchet" unless scan_only
      ok, body = capture(*census)
      dup_ok, dup_body = capture(RUBY, File.join(MASTER, "tools", "dup_census.rb"))
      both = ok && dup_ok
      verdict = "sprawl: #{both ? "at or under every recorded low" : "over a recorded low"}"
      [both, body + dup_body + [verdict], both ? 0 : 1]
    end

    # [ok, body, exitstatus] — the status, because 3 is a third state a boolean
    # cannot carry.
    def capture(*cmd, chdir: MASTER, env: {})
      out, status = Open3.capture2e(ENV.to_h.merge(env), *cmd, chdir: chdir)
      [status.success?, out.lines.map(&:rstrip).reject(&:empty?), status.exitstatus]
    rescue StandardError => e
      [false, ["#{e.class}: #{e.message}"], 1]
    end

    # Untracked files count: a stage that drops a new file in is a stage that
    # changed the tree, and much of the damage this chain attributes arrives so.
    def dirty
      out, status = Open3.capture2e("git", "status", "--porcelain", "-z", chdir: ROOT)
      return [] unless status.success?

      out.split("\0").filter_map { |entry| entry[3..] }.reject(&:empty?)
    end

    # The instrument's own summary line, not the last line printed — the rule
    # tools/sweep.rb learned when design_baseline printed its verdict above its
    # detail and "last line" read a detail row as the verdict.
    def verdict(body)
      summary = body.reverse.find { |line| line.match?(/\A[a-z][a-z_0-9]*:\s/) }
      (summary || body.last).to_s.strip
    end

    # The seam to the council's own diagnosis, not invented here.
    # Deliberation#failure_reason slugs each persona's failure and quorum_error
    # tallies them ("quorum not reached (2/26) — 24x insufficient_credits");
    # bin/gate matches that on INCONCLUSIVE and --semantic-only returns 3 rather
    # than aborting. The reason arrives in the stage's verdict line, so this only
    # reads the status, and a richer predicate later changes this method alone.
    def classify(ok, exitstatus)
      return "ok" if ok
      return "skipped" if exitstatus == 3

      "failed"
    end

    def run(scan_only:, only: nil, list: false)
      all = stages(scan_only:)
      selected = only&.any? ? all.select { |stage| only.include?(stage.name) } : all
      abort "gate: no stage named #{only.join(", ")} (have: #{all.map(&:name).join(", ")})" if selected.empty?
      return explain(selected, scan_only:) if list

      report(selected, scan_only:)
    end

    def explain(selected, scan_only:)
      puts "gate: #{scan_only ? "scan-only" : "full-fix"} — #{selected.size} stage(s)"
      selected.each { |s| puts format("  %-9s %s%s", s.name, s.purpose, s.mutates ? "  [writes]" : "") }
      0
    end

    def report(selected, scan_only:)
      foreign = dirty
      mode = scan_only ? "scan-only (writes nothing)" : "full-fix (writes)"
      puts "gate: #{mode} — #{selected.map(&:name).join(" -> ")}"
      announce_foreign(foreign)

      seen = foreign.dup
      results = selected.each_with_index.map do |stage, index|
        puts "gate: #{index + 1}/#{selected.size} #{stage.name}"
        result = run_stage(stage, seen)
        seen |= result.changed
        result
      end
      summarise(results, foreign)
    end

    def run_stage(stage, seen)
      puts "\n== #{stage.name}: #{stage.purpose}"
      ok, body, exitstatus = stage.run.call
      changed = dirty - seen
      state = classify(ok, exitstatus)
      state = "failed" if changed.any? && !stage.mutates
      puts "   #{state}: #{verdict(body)}"
      body.last(state == "ok" ? 0 : 12).each { |line| puts "   | #{line}" }
      announce_changed(stage, changed)
      Result.new(stage: stage.name, state:, summary: verdict(body), changed:)
    end

    def announce_foreign(foreign)
      return puts("gate: tree clean at the start — everything below belongs to this run") if foreign.empty?

      puts "gate: #{foreign.size} file(s) were ALREADY modified before this run — not this chain's, leave them:"
      foreign.first(20).each { |path| puts "   ~ #{path}" }
      puts "   ~ … and #{foreign.size - 20} more" if foreign.size > 20
    end

    def announce_changed(stage, changed)
      return if changed.empty?

      label = stage.mutates ? "changed by #{stage.name}" : "CHANGED BY A STAGE THAT PROMISED NOT TO WRITE"
      puts "   #{changed.size} file(s) #{label}:"
      changed.first(30).each { |path| puts "   + #{path}#{path.match?(GENERATED) ? "   GENERATED — revert" : ""}" }
      puts "   + … and #{changed.size - 30} more" if changed.size > 30
    end

    def summarise(results, foreign)
      changed = results.flat_map(&:changed)
      generated = changed.grep(GENERATED)
      clean = results.count { |result| result.state == "ok" }
      puts "\ngate: #{clean}/#{results.size} stage(s) clean, #{changed.size} changed, #{foreign.size} foreign"
      results.select { |r| r.state == "skipped" }.each { |r| puts "gate: #{r.stage} NOT MEASURED — #{r.summary}" }
      results.select { |r| r.state == "failed" }.each { |r| puts "gate: #{r.stage} FAILED — #{r.summary}" }
      generated.each { |path| puts "gate: generated file rewritten, revert it — #{path}" }

      return 1 if results.any? { |r| r.state == "failed" } || generated.any?
      return 3 if results.any? { |r| r.state == "skipped" }

      puts "gate: clean"
      0
    end
  end
end
