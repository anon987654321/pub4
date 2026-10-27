# frozen_string_literal: true

require_relative "../master"

require "digest"
require "fileutils"
require "json"
require "tempfile"
require "open3"
require "rbconfig"
require "tmpdir"
require "operator/check_heartbeat"
require "operator/ruby_runner"
require "bundler"
require_relative "strict_mode"
require_relative "check_regression"
require_relative "check_heartbeat"
require_relative "../trace/dmesg"
require_relative "../boot/paths"
require_relative "../fix/resource_budget"
require_relative "../fix/work_lane"
require_relative "../fix/rails_app"
require_relative "../io/exec"

module Operator
  # Every check in the repo, in one order, fixing as it goes.
  #
  # The pieces all existed and nothing ran them together: `bin/check --ladder` held the
  # scanner chain, `MASTER/checks/runner.rb --all` the app checks, `bin/check` the
  # suites, `bin/operator measure` the ratchets, `tools/sprawl_census.rb` the shape of
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
  #   MASTER/checks/runner.rb already spells for a precondition it never met.
  module CheckChain
    ROOT = File.expand_path("../../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")
    RUBY = Operator::RubyRunner.check_ruby
    BUNDLE = Operator::RubyRunner.bundle_cmd
    CHILD_TIMEOUT_S = 1_800
    DISK_POLL_INTERVAL_S = 30
    SUITE_TIMEOUTS = {
      "MASTER" => 1_800,
      "RAILS contracts" => 1_200,
      "brgen suite" => 1_200,
      "amber suite" => 1_200,
      "bsdports suite" => 1_200,
      "OPENBSD" => 600,
      "tools" => 900,
      "STUDIO media" => 900,
    }.freeze

    # Paths nothing writes by hand. `bin/check --ladder` has said in a comment for months
    # that scanner.rb skips `cache` but not `.cache`, so /fix descends into
    # MASTER/tools' generated lora/**/.cache/** copies — a warning with no reader.
    # This is the reader: a rewritten generated file is named, and fails the run.
    GENERATED = %r{/\.cache/|/node_modules/|/public/assets/|/app/assets/builds/|\.lock\z}

    # The panel argues until the late idea arrives and hands back a long list, and
    # an unbounded queue of unattended edits on a shared checkout is the failure
    # this file makes attributable. So the queue has a floor under it.
    PICK_BUDGET = Integer(ENV.fetch("PUB4_CHECK_COUNCIL_PICKS", "5"))

    class BaselineMutation < StandardError; end
    class InvalidVerificationScope < StandardError; end

    # ok / failed / skipped; skipped is the one that matters.
    Result = Struct.new(:stage, :state, :summary, :changed, :body, keyword_init: true)

    # `mutates` is a claim, and the attribution below tests it: a stage declared
    # non-mutating that changes a file fails the run.
    Stage = Struct.new(:name, :purpose, :mutates, :run, keyword_init: true)

    module_function

    # The entry point, and the two methods under it are the whole of what
    # bin/operator calls. Everything below is a stage or a helper one of these three
    # reaches, so the file reads in the order the ladder runs rather than the
    # order it was written.
    TREES = MasterPaths::TREES

    # /fix already owns observation, council critique and repair. Its verification
    # tail proves the repaired tree without recursively invoking /fix or debating
    # the same tree a second time.
    def verify_fix(target:, baseline: nil)
      selected = verification_stages(target)
      return [0, []] if selected.empty?

      status, changed = report(selected, scan_only: true, trees: trees_for_target(target), return_results: true)
      if status.zero? && changed.empty?
        remember_verified_snapshot(target)
        return [0, changed]
      end
      return [status, changed] unless status == 1 && baseline && changed.empty?

      unmeasured = Array(@last_results).select { |result| result.state == "skipped" }
      if unmeasured.any?
        stages = unmeasured.map { |result| "#{result.stage} (#{result.summary})" }.first(6).join(", ")
        more = unmeasured.size > 6 ? " and #{unmeasured.size - 6} more" : ""
        Master::Trace::Dmesg.status(
          "check0", "INCONCLUSIVE, regression comparison withheld; #{unmeasured.size} stage(s) unmeasured: #{stages}#{more}"
        )
        return [status, changed]
      end

      # Standing failures are not this run's to clear. A run passes when it adds
      # no failure the tree did not have; nothing is moved or relaxed.
      regressions = CheckRegression.new(baseline).regressions(@last_results)
      if regressions.empty?
        Master::Trace::Dmesg.status("check0", "no regression against the starting baseline, #{baseline.size} stage(s) failed before this run")
        remember_verified_snapshot(target)
        return [0, changed]
      end

      regressions.each { |line| Master::Trace::Dmesg.status("check0", "regression, #{line}") }
      [status, changed]
    end

    # These snapshots are only cached after a verified pass, then re-keyed after
    # the final commit so an identical tree can reuse its regression baseline.
    def clear_verified_fix_snapshots!
      @verified_fix_snapshots = {}
    end

    def remember_verified_snapshot(target)
      (@verified_fix_snapshots ||= {})[baseline_scope_key(target)] = CheckRegression.snapshot(@last_results)
    end

    def persist_verified_baselines!(targets)
      pending = @verified_fix_snapshots || {}
      Array(targets).each do |target|
        scope = baseline_scope_key(target)
        snapshot = pending.delete(scope)
        next unless snapshot

        begin
          key = baseline_key(scope == "all" ? "all" : scope)
          write_baseline(key, snapshot)
        rescue StandardError => e
          # This cache shortens later runs; it is never part of repair success.
          Master::Trace::Dmesg.status("check0", "verified baseline cache not persisted for #{scope}, #{e.class}")
        end
      end
      @verified_fix_snapshots = pending
      true
    end

    # What already fails before /fix touches anything: stage name => failing lines.
    # One scan-only ladder, remembered by commit and working-tree content so a second run
    # reuses it. A passing or failing ladder is stored alike: the baseline is what failed.
    # The isolated worktree's final proof must reuse the candidate snapshot
    # recorded by the successful inner /fix. It must not create a baseline here:
    # that would compare the candidate with itself and prove nothing.
    def verify_cached_fix(target:)
      key = baseline_key(target)
      baseline = read_baseline(key)
      unless baseline
        scope = baseline_scope_key(target)
        Master::Trace::Dmesg.status("check0", "INCONCLUSIVE, no verified candidate baseline for #{scope}")
        return [3, []]
      end

      verify_fix(target:, baseline:)
    rescue StandardError => e
      Master::Trace::Dmesg.status("check0", "INCONCLUSIVE, final regression proof failed, #{e.class}: #{e.message}")
      [3, []]
    end

    def baseline(target:)
      selected = verification_stages(target)
      return {} if selected.empty?

      trees = trees_for_target(target)
      key = baseline_key(target)
      cached = read_baseline(key)
      if cached
        Master::Trace::Dmesg.status("baseline0", "read-only pre-repair proof reused for #{key[0, 12]}, no ladder rerun")
        return cached
      end
      # The target cache key fingerprints untracked files only in its scope.
      # Preflight promises the entire shared checkout will remain read-only,
      # including dirty/untracked paths from other trees, so the whole checkout's
      # working bytes bracket the measurement.
      checkout_before = checkout_snapshot

      Master::Trace::Dmesg.status(
        "baseline0",
        "read-only pre-repair proof starting, trees=#{trees.join(", ")}, stages=#{selected.map(&:name).join(", ")}; repair follows",
      )
      status, changed = report(selected, scan_only: true, trees:, return_results: true)
      # Stage attribution excludes pre-existing dirty paths so /fix never claims
      # another session's edits. That means it cannot, alone, detect a read-only
      # stage overwriting one of those files. Fingerprint the checkout again
      # before saving any baseline; it includes tracked diffs and non-ignored
      # untracked files even when their paths were already dirty at stage start.
      moved = checkout_changes(checkout_before)
      # The stages measure `trees`; a change in another tree is another writer's in the shared
      # checkout, not a read-only stage's write. A STUDIO edit made during a MASTER baseline
      # blocked the whole run, so those are named and the baseline stands.
      changed, moved = [changed, moved].map { |paths| inside_trees(paths, trees) }
      if changed.any? || moved.any?
        paths = (changed + moved).uniq
        details = paths.first(12).join(", ")
        more = paths.size > 12 ? " and #{paths.size - 12} more" : ""
        message = if changed.any?
                    "read-only pre-repair proof changed #{changed.size} attributed path(s): #{details}#{more}"
                  else
                    "read-only pre-repair proof changed checkout state; visible path(s): #{details}#{more}"
                  end
        Master::Trace::Dmesg.status("baseline0", "BLOCKED — #{message}")
        raise BaselineMutation, message
      end

      snapshot = CheckRegression.snapshot(@last_results)
      write_baseline(key, snapshot)
      outcome = case status
                when 0 then "clean baseline"
                when 1 then "existing failures recorded"
                else "INCONCLUSIVE, status=#{status}"
                end
      Master::Trace::Dmesg.status(
        "baseline0",
        "pre-repair proof captured, #{outcome}, stages=#{selected.size}, attributed_changes=#{changed.size}",
      )
      snapshot
    end

    BASELINE_FILE = File.join(MASTER, ".master", "check_baseline.json")

    def baseline_key(target, root: ROOT, trees: trees_for_target(target))
      # The target trees' own content, not the whole checkout's: another writer's commit or edit
      # in a different tree changed the key and the baseline ladder ran again.
      tree_names = Array(trees).map(&:to_s).reject(&:empty?)
      head = tree_names.map { |tree| committed_version(root, tree) }.join(",")
      diff, diff_status = Master::Io::Exec.capture2("git", "diff", "HEAD", "--binary", "--", *tree_names, chdir: root)
      raise "check baseline fingerprint: git diff failed" unless diff_status.success?

      untracked, untracked_status = Master::Io::Exec.capture2(
        "git", "ls-files", "--others", "--exclude-standard", "-z", chdir: root
      )
      raise "check baseline fingerprint: git ls-files failed" unless untracked_status.success?

      paths = untracked.split("\0").reject(&:empty?).select do |relative|
        tree_names.any? { |tree| relative == tree || relative.start_with?("#{tree}/") }
      end
      untracked_fingerprint = paths.sort.map { |relative| fingerprint_untracked(root, relative) }.join("\0")
      scope = baseline_scope_key_for(tree_names)
      # The lane is part of the key: a code-lane baseline measured no browser check.
      Digest::SHA256.hexdigest([head.strip, scope, diff, untracked_fingerprint, verification_only.join(","),
                                Master::Fix::WorkLane.current].join("\0"))
    end

    # The bytes of every changed or untracked path in the whole repository, root-level files
    # included. It brackets a read-only measurement only. HEAD is left out: other sessions commit
    # to this checkout every few minutes, and a thirty-minute baseline that counted HEAD was
    # blocked by every commit, though a commit leaves the working tree as it found it.
    def checkout_snapshot(root: ROOT)
      out, status = Master::Io::Exec.capture2e("git", "status", "--porcelain=v1", "-z", "--untracked-files=all",
                                               chdir: root)
      raise "checkout snapshot: git status failed: #{out.to_s.strip}" unless status.success?

      parse_dirty_paths(out).sort.to_h { |relative| [relative, fingerprint_untracked(root, relative)] }
    end

    # Paths dirty now whose bytes the snapshot did not hold. A path committed since reads clean
    # and drops out.
    def checkout_changes(before, root: ROOT)
      checkout_snapshot(root:).reject { |relative, print| before[relative] == print }.keys
    end

    def committed_version(root, tree)
      out, status = Master::Io::Exec.capture2("git", "rev-parse", "HEAD:#{tree}", chdir: root)
      raise "check baseline fingerprint: git rev-parse failed for HEAD:#{tree}" unless status.success?

      out.strip
    end

    def baseline_scope_key(target)
      baseline_scope_key_for(trees_for_target(target))
    end

    def baseline_scope_key_for(trees)
      names = Array(trees).map(&:to_s).reject(&:empty?).map(&:upcase).uniq.sort
      names == TREES.sort ? "all" : names.join(",")
    end

    def fingerprint_untracked(root, relative)
      path = File.join(root, relative)
      return "#{relative}\0symlink\0#{File.readlink(path)}" if File.symlink?(path)
      return "#{relative}\0missing" unless File.file?(path)

      "#{relative}\0file\0#{File.stat(path).mode & 0o7777}\0#{Digest::SHA256.file(path).hexdigest}"
    end

    MAX_BASELINE_RECORDS = 16

    def read_baseline(key)
      baseline_entries[key]
    end

    def baseline_entries
      stored = JSON.parse(File.read(BASELINE_FILE))
      entries = stored["entries"] if stored.is_a?(Hash)
      if entries.is_a?(Hash)
        return entries.select { |record_key, value| record_key.is_a?(String) && value.is_a?(Hash) }
      end

      # Read the single-record format written by earlier MASTER versions.
      return { stored["key"] => stored["snapshot"] } if
        stored.is_a?(Hash) && stored["key"].is_a?(String) && stored["snapshot"].is_a?(Hash)

      {}
    rescue Errno::ENOENT, JSON::ParserError, TypeError
      {}
    end

    def write_baseline(key, snapshot)
      entries = baseline_entries
      entries.delete(key)
      entries[key] = snapshot
      entries = entries.to_a.last(MAX_BASELINE_RECORDS).to_h
      FileUtils.mkdir_p(File.dirname(BASELINE_FILE))
      Tempfile.create(["check-baseline", ".json"], File.dirname(BASELINE_FILE)) do |file|
        file.write(JSON.generate("version" => 2, "entries" => entries))
        file.flush
        file.fsync
        File.rename(file.path, BASELINE_FILE)
      end
    end

    PASS_PROVEN_TREES = %w[MASTER OPENBSD RAILS].freeze

    def verification_stages(target)
      trees = trees_for_target(target)
      selected = stages(scan_only: true, trees:).reject { |stage| stage.name == "council" }
      # The /fix pass proves these trees itself, before and after its repair: MASTER and OPENBSD
      # with their suites (Pass's proof), RAILS with the source stage, which owns the complete
      # Rails premerge proof. Running the suites here as well ran them four times per /fix.
      selected = selected.reject { |stage| stage.name == "suites" } if (trees - PASS_PROVEN_TREES).empty?
      # The visual lane's own sweep, taken before its repairs and again after them, is its proof;
      # the source stage would render the same routes twice more around it.
      selected = selected.reject { |stage| stage.name == "source" } if Master::Fix::WorkLane.visual?
      # Verification is measurement only. Every selected stage is scan-only;
      # a verification tail must never become a second repair pass under
      # another name. Council stays excluded because provider availability is
      # not a source-tree proof and can be separately reported by /critique.
      only = verification_only
      return selected if only.empty?

      all_proof_stages = stages(scan_only: true, trees: TREES).map(&:name).reject { |name| name == "council" }
      unknown = only - all_proof_stages
      raise InvalidVerificationScope, "unknown/non-proof stage(s): #{unknown.join(", ")}" if unknown.any?

      missing = only - selected.map(&:name)
      if missing.any?
        raise InvalidVerificationScope,
              "stage(s) #{missing.join(", ")} do not apply to target #{target.inspect}; no proof was run"
      end

      selected.select { |stage| only.include?(stage.name) }
    end

    # MASTER_FIX_CHECK_STAGES=lexical,openbsd limits the verification ladder to those stages.
    # The Rails "source" stage boots the apps and runs the rendered checks, about twenty-five
    # minutes before the first repair; a source-only run names the stages it wants instead.
    # The same list picks the baseline's stages and the closing verification's, so the
    # regression check always compares like with like.
    def verification_only
      ENV.fetch("MASTER_FIX_CHECK_STAGES", "").split(/[,\s]+/).reject(&:empty?)
    end

    # No list means every stage; a list means only the named ones.
    def verification_stage?(name)
      only = verification_only
      only.empty? || only.include?(name.to_s)
    end

    # Paths in another of the four trees are another writer's: named and dropped. The measured trees
    # and anything at the repository root still count, since no other tree's owner writes there.
    def inside_trees(paths, trees)
      others = TREES - trees
      outside, inside = Array(paths).partition { |path| others.any? { |tree| path.start_with?("#{tree}/") } }
      unless outside.empty?
        Master::Trace::Dmesg.status("baseline0", "another writer changed #{outside.size} path(s) outside #{trees.join(", ")} " \
                                                 "during the baseline: #{outside.first(5).join(", ")}")
      end
      inside
    end

    def trees_for_target(target)
      text = target.to_s.strip
      tree_names = text.split(/[,\s]+/).reject(&:empty?).map(&:upcase).uniq.sort
      return TREES if tree_names == TREES.sort

      relative = text.delete_prefix("../")
      abs = case relative.upcase
            # The CLI runs from MASTER: an omitted target or "." means this
            # tree, not the repository root. Whole-repo work stays explicit.
            when "", ".", "MASTER" then MASTER
            when "ALL", "EVERYTHING" then ROOT
            when "RAILS" then File.join(ROOT, "RAILS")
            when "OPENBSD" then File.join(ROOT, "OPENBSD")
            when "STUDIO" then File.join(ROOT, "STUDIO")
            else File.expand_path(text, ROOT)
            end
      return TREES if abs == ROOT
      return ["RAILS"] if abs == File.join(ROOT, "RAILS") || abs.start_with?("#{File.join(ROOT, "RAILS")}/")
      return ["OPENBSD"] if abs == File.join(ROOT, "OPENBSD") || abs.start_with?("#{File.join(ROOT, "OPENBSD")}/")
      return ["STUDIO"] if abs == File.join(ROOT, "STUDIO") || abs.start_with?("#{File.join(ROOT, "STUDIO")}/")
      return ["MASTER"] if abs == MASTER || abs.start_with?("#{MASTER}/")

      # Check targets like `lib/io` are MASTER-relative shorthand when the
      # operator is invoked from the repository root. Keep the four-tree
      # boundary strict while resolving that intentional CLI form first.
      master_relative = File.expand_path(target.to_s, MASTER)
      return ["MASTER"] if File.file?(master_relative) || File.directory?(master_relative)

      Master::Trace::Dmesg.status("check0", "target outside pub4 trees, #{target}")
      raise ArgumentError, "target outside pub4 trees: #{target}"
    end

    def run(scan_only:, only: nil, list: false, trees: nil)
      trees = normalise_trees(trees)
      all = stages(scan_only:, trees:)
      selected = only&.any? ? all.select { |stage| only.include?(stage.name) } : all
      if selected.empty?
        Master::Trace::Dmesg.status("check0", "no stage named #{only.join(", ")}, have #{all.map(&:name).join(", ")}")
        return 1
      end
      return explain(selected, scan_only:, trees:) if list

      report(selected, scan_only:, trees:)
    end

    # An unknown tree name is refused. The whole point of --tree is to run less,
    # so a typo that quietly narrowed the ladder to nothing would report a clean
    # repo on the strength of having measured none of it.
    def normalise_trees(trees)
      named = Array(trees).flat_map { |value| value.to_s.split(",") }.map(&:upcase).reject(&:empty?)
      return TREES if named.empty?

      unknown = named - TREES
      if unknown.any?
        Master::Trace::Dmesg.status("check0", "no tree named #{unknown.join(", ")}, have #{TREES.join(", ")}")
        raise ArgumentError, "no tree named #{unknown.join(", ")}"
      end
      named
    end

    def explain(selected, scan_only:, trees:)
      Master::Trace::Dmesg.attach(
        "check0", "master0",
        "#{scan_only ? "scan-only" : "full fix"}, #{selected.size} stages, #{trees.join(", ")}"
      )
      selected.each do |stage|
        unit = stage_unit(stage)
        detail = stage.mutates ? "#{stage.purpose}, writes" : stage.purpose
        Master::Trace::Dmesg.attach(unit, "check0", detail)
      end
      0
    end

    def report(selected, scan_only:, trees:, return_results: false)
      foreign = dirty
      mode = scan_only ? "scan-only, writes nothing" : "full fix, writes"
      Master::Trace::Dmesg.attach(
        "check0", "master0",
        "#{mode}, #{selected.size} stages, #{trees.join(", ")}"
      )
      announce_foreign(foreign)

      seen = foreign.dup
      results = selected.map do |stage|
        result = run_stage(stage, seen)
        seen |= result.changed
        result
      end
      status = summarise(results, foreign)
      @last_results = results
      return [status, results.flat_map(&:changed)] if return_results

      status
    end

    # The ladder. Order is not taste: the deterministic fixers run first so
    # everything after measures the fixed tree; the ratchets run after the suites
    # because a fix moves the numbers; sprawl runs after the ratchets because it
    # only locks in a fall that already happened; and the council runs last
    # because it is the only stage that costs money and the only one that
    # currently cannot answer — a tier with no answer must not stand between the
    # rest of the ladder and its verdict.
    # Narrowing by tree drops stages rather than shrinking them, because that is
    # what each stage is: the RAILS check runner has nothing to say about MASTER/tools,
    # and brgen's suite is not a MASTER session's business. Two stages stay
    # whole under every --tree — the ratchets and the sprawl census are
    # repo-wide measurements by definition, and both are cheap.
    def stages(scan_only:, trees: TREES)
      scope = trees == TREES ? "all four trees" : trees.join(", ")
      [
        lexical_stage(scan_only:, trees:, scope:),
        rails_stage(scan_only:, trees:),
        openbsd_stage(trees:),
        rehearse_stage(trees:),
        suites_stage(trees:),
        ratchets_stage(trees:),
        sprawl_stage(scan_only:),
        council_stage(scan_only:, trees:),
      ].compact
    end

    def lexical_stage(scan_only:, trees:, scope:)
      action = scan_only ? "measuring without writes" : "autofixing"
      Stage.new(
        name: "lexical",
        purpose: "law/ and the scan registry over #{scope}, #{action}",
        mutates: !scan_only,
        run: ->(progress) { check("--lexical-only", scan_only:, trees:, env: progress) },
      )
    end

    def rails_stage(scan_only:, trees:)
      return unless trees.include?("RAILS")

      Stage.new(
        name: "source",
        purpose: "every RAILS check, source/rendered repair, then full Rails verification",
        mutates: !scan_only,
        run: -> { rails_verification(scan_only:) },
      )
    end

    def openbsd_stage(trees:)
      return unless trees.include?("OPENBSD")

      Stage.new(
        name: "openbsd",
        purpose: "every OpenBSD config, shell and deploy check",
        mutates: false,
        run: -> { openbsd_checks },
      )
    end

    # The deploy checks that need no Rails boot, in seconds, so a moved path or a
    # stale mirror list fails here and not forty minutes into a run on vm23.
    def rehearse_stage(trees:)
      return unless trees.include?("OPENBSD") || trees.include?("RAILS")

      Stage.new(
        name: "rehearse",
        purpose: "the deploy rehearsal: CI lints and the static deploy contracts (OPENBSD/bin/rehearse)",
        mutates: false,
        run: -> { capture(RUBY, File.join(ROOT, "OPENBSD", "bin", "rehearse"), chdir: ROOT) },
      )
    end

    def suites_stage(trees:)
      Stage.new(
        name: "suites",
        purpose: suite_purpose(trees),
        mutates: false,
        run: -> { suites(trees) },
      )
    end

    def suite_purpose(trees)
      scope = trees == TREES ? "all four trees" : trees.join(", ")
      "complete test suites over #{scope}"
    end

    # A narrower check measures only its trees' ceilings: a MASTER proof spent fifteen
    # minutes scanning every RAILS view for design_baseline, which no MASTER edit moves.
    def ratchets_stage(trees:)
      scope = trees == TREES ? [] : ["--trees=#{trees.join(",")}"]

      Stage.new(
        name: "ratchets",
        purpose: "every recorded ceiling, current beside it",
        mutates: false,
        run: -> { capture(RUBY, File.join(MASTER, "bin", "operator"), "measure", "--deep", *scope) },
      )
    end

    def sprawl_stage(scan_only:)
      Stage.new(
        name: "sprawl",
        purpose: "lone dirs, stutter, vague names, duplicate files",
        mutates: !scan_only,
        run: -> { sprawl(scan_only:) },
      )
    end

    def council_stage(scan_only:, trees:)
      Stage.new(
        name: "council",
        purpose: "/critique and /review, then the panel's picks back through the runtime",
        mutates: council_fix?(scan_only:),
        run: -> { council(scan_only:, trees:) },
      )
    end

    # /critique IS the council: dispatch_critique hands the path to
    # Review::Council::Critique, which runs the persona panel, the adversarial
    # round and the cherry-pick. A second one here is a second debate.
    def council(scan_only:, trees: TREES)
      ok, body, exitstatus = check("--semantic-only", scan_only:, trees:)
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

      section = File.read(latest).split("## cherry-picked", 2)[1].to_s
      return [] if section.empty?

      section.lines.filter_map { |line| line.strip[/\A-\s+(.+)\z/, 1] }.reject(&:empty?)
    rescue StandardError => e
      raise "council: harvest under #{dir} unreadable: #{e.class}: #{e.message}"
    end

    # Never in scan-only: that mode's promise is a shared checkout untouched.
    # PUB4_CHECK_COUNCIL_FIX=0 turns it off in full-fix too, for a run where the
    # panel argues and nothing moves.
    def council_fix?(scan_only:)
      !scan_only && ENV.fetch("PUB4_CHECK_COUNCIL_FIX", "1") != "0"
    end

    def strict_env
      Operator::StrictMode.flags
    end

    def check(tier, scan_only:, trees: TREES, env: {})
      scope = trees == TREES ? [] : ["--tree=#{trees.join(',')}"]
      capture(RUBY, File.join(MASTER, "bin", "check"), tier, *scope, *(scan_only ? ["--scan-only"] : []), env:)
    end

    # CHECK_AUTOFIX defaults to on; naming it keeps scan-only honest either way.
    # Under the Ruby the repo pins, as the app suites below run. runner.rb refuses
    # any other, so launched with this process's Ruby every check was skipped and
    # the stage reported one refusal as its whole result.
def rails_checks(scan_only:, strict_inconclusive: false)
  CheckHeartbeat.around("rails checks") do |progress|
    env = strict_env.merge(progress).merge("CHECK_AUTOFIX" => scan_only ? "0" : "1", **Master::Fix::WorkLane.check_env)
    # A proof cannot pass a check that measured nothing. The normal contribution
    # mode remains permissive; /fix opts into strict inconclusive handling here
    # because this child environment is constructed explicitly.
    env["CHECK_STRICT_INCONCLUSIVE"] = "1" if strict_inconclusive
    capture(RUBY, File.join(MASTER, "checks", "runner.rb"), "--all",
            chdir: File.join(ROOT, "RAILS"), env:)
  end
end

    # The repair-aware runner owns deterministic source/rendered corrections;
    # premerge is the read-only proof that every Rails test, coverage dimension
    # and PWA/runtime check survives the repaired tree.
    def rails_verification(scan_only:)
      ok, body, status = rails_checks(scan_only:)
      return [ok, body, status] unless ok

      premerge = File.join(MASTER, "tools", "rails", "premerge.rb")
      return [false, body + ["rails premerge missing: #{premerge}"], 1] unless File.file?(premerge)

verified, verification_body, verification_status = CheckHeartbeat.around("rails premerge") do |_progress|
  capture(RUBY, premerge, chdir: File.join(ROOT, "RAILS"), env: strict_env.merge("MASTER_FIX_VERIFY" => "1"))
end
      [verified, body + ["rails premerge: #{verified ? "ok" : "FAIL"}"] + verification_body, verification_status]
    end

    def openbsd_checks
      capture(RUBY, File.join(ROOT, "OPENBSD", "bin", "check-openbsd"),
              chdir: ROOT, env: strict_env)
    end

    # Keep this inventory aligned with OPENBSD/test/run_all.rb. It is recursive
    # so a test moved beneath test/ stays measured, and empty discovery must fail
    # rather than claim a green suite that ran nothing.
    OPENBSD_SUITE = <<~SUITE
      # encoding: UTF-8
      files = Dir["test/**/test_*.rb"].sort
      abort("openbsd: no test files discovered") if files.empty?
      failed = files.reject { |f| system(RbConfig.ruby, f) }
      abort("openbsd: \#{failed.size} of \#{files.size} file(s) failed — \#{failed.join(", ")}") if failed.any?
    SUITE

    # Whole suites, not the ones the diff touches: a green over hand-picked tests
    # is unmeasured. This is `bin/operator test`'s mapping with every path in it.
    # The fifth element is the tree the suite proves, so --tree can drop the ones
    # that prove another. It is not derivable from the working directory: MASTER/tools'
    # suite runs from MASTER, because the rake task lives there.
    def suite_jobs(trees = TREES)
      [
        ["MASTER", [RUBY, File.join(MASTER, "bin", "check"), "--profile=ci"], MASTER, {}, "MASTER"],
        ["RAILS contracts", [RUBY, "test/run_all.rb"], File.join(ROOT, "RAILS"), {}, "RAILS"],
        *%w[brgen amber bsdports].map do |app|
          ["#{app} suite", [RUBY, BUNDLE, "exec", RUBY, "-S", "rails", "test"],
           File.join(ROOT, "RAILS", app), {}, "RAILS"]
        end,
        ["OPENBSD", [RUBY, "-e", OPENBSD_SUITE], File.join(ROOT, "OPENBSD"), {}, "OPENBSD"],
        ["tools", [RUBY, "-S", "rake"], File.join(MASTER, "tools"), {}, "MASTER", true],
        ["STUDIO media", [RUBY, "-S", "rake", "test"], File.join(ROOT, "STUDIO"), {}, "STUDIO", true],
      ].select { |job| trees.include?(job[4]) }
    end

    def suites(trees = TREES)
      results = suite_jobs(trees).map do |name, cmd, dir, env, _tree, unbundled|
        timeout_s = suite_timeout_s(name)
        Master::Trace::Dmesg.status("suite0", "#{name} starting, timeout #{timeout_s}s")
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ok, out = capture(*cmd, chdir: dir, env:, unbundled:, timeout_s:, label: name, heartbeat_unit: "suite0")
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round
        Master::Trace::Dmesg.status("suite0", "#{name} #{ok ? "ok" : "FAIL"}, elapsed #{elapsed}s")
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
      planner = [RUBY, File.join(MASTER, "tools", "sprawl_plan.rb")]
      planner << "--write" unless scan_only
      plan_ok, plan_body = capture(*planner)
      census = [RUBY, File.join(MASTER, "lib", "operator", "sprawl_census.rb")]
      census << "--ratchet" unless scan_only
      ok, body = capture(*census)
      dup_ok, dup_body = capture(RUBY, File.join(MASTER, "tools", "dup_census.rb"))
      both = plan_ok && ok && dup_ok
      verdict = "sprawl: #{both ? "at or under every recorded low" : "over a recorded low"}"
      [both, plan_body + body + dup_body + [verdict], both ? 0 : 1]
    end

    # Every stage child is a Ruby that activates its own bundle, often a
    # different Ruby: a parent on MASTER's private store handed rbenv's ruby
    # Homebrew's bundler/setup in RUBYOPT and asked for bundler 4.0.11, which it
    # does not have, and the child exited 1 before its first line. Nor does a
    # check stage need the parent's lock: a descriptor number without the
    # descriptor is a poisoned inheritance path, so the caller cannot pass it.
    def stage_child_env(env)
      foreign = Master::Fix::RailsApp::FOREIGN_BUNDLE.to_h { |key| [key, nil] }

      foreign.merge("MASTER_INTERNAL_CHILD" => "1", "MASTER_CONTROL_PLANE" => "0")
             .merge(env)
             .merge("MASTER_PROCESS_LOCK_FD" => nil)
    end

    # [ok, body, exitstatus] — the status, because 3 is a third state a boolean
    # cannot carry.
    #
    # Every stage is a child process, and that nesting stays. The process is what
    # gives a stage its own exit status, bin/check --ladder's stage timeouts and a window
    # for attributing changed files; running stages in-process saves boot time
    # and loses all three.
    def capture(*cmd, chdir: MASTER, env: {}, unbundled: false, timeout_s: nil,
                disk_poll_s: DISK_POLL_INTERVAL_S, label: nil, heartbeat_unit: "check0")
      timeout_s = child_timeout_s if timeout_s.nil?
      paths = [ROOT, chdir, Dir.tmpdir]
      display = label.to_s.empty? ? nil : "#{label}: "
      Master::Trace::Dmesg.status(heartbeat_unit, "#{label} running") if label
      initial = disk_state(paths)
      if initial[:critical]
        reason = "#{display}#{disk_stop_reason(initial, prefix: "disk preflight")}"
        Master::Trace::Dmesg.status(heartbeat_unit, reason)
        return [false, [reason], 1]
      end

      runner = lambda do
        output = +""
        stopped_for = nil
        stop_lock = Mutex.new
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        watchdog = nil
        Open3.popen2e(ENV.to_h.merge(stage_child_env(env)), *cmd, chdir:, pgroup: true) do |stdin, stream, wait|
          stdin.close
          last_heartbeat = 0.0
          watchdog = Thread.new do
            loop do
              sleep [disk_poll_s.to_f, 0.01].max
              elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
              if label && elapsed >= last_heartbeat + 28
                Master::Trace::Dmesg.status(heartbeat_unit, "#{label} running, elapsed #{elapsed.round}s")
                last_heartbeat = elapsed
              end
              if timeout_s && elapsed >= timeout_s.to_f
                stop_lock.synchronize { stopped_for ||= "#{display}check child timeout after #{timeout_s.to_f.round(1)}s" }
                terminate_child_group(wait.pid)
                break
              end

              current = disk_state(paths)
              next unless current[:critical]

              stop_lock.synchronize { stopped_for ||= "#{display}#{disk_stop_reason(current, prefix: "disk guard")}" }
              terminate_child_group(wait.pid)
              break
            end
          end

          stream.each_line do |line|
            output << line
            Master::Trace::Dmesg.terminal_write do |io|
              io.write(line)
              io.flush
            end
          end
          status = wait.value
          watchdog.kill if watchdog&.alive?
          watchdog&.join
          stopped_for = stop_lock.synchronize { stopped_for }
          if stopped_for
            output << "#{stopped_for}\n"
            [false, output, stopped_for.include?("check child timeout") ? 124 : 1]
          else
            [status.success?, output, status.exitstatus]
          end
        ensure
          watchdog&.kill
          watchdog&.join
        end
      end
      ok, out, exitstatus = if unbundled && defined?(Bundler)
                              Bundler.with_unbundled_env { runner.call }
                            else
                              runner.call
                            end
      [ok, out.lines.map(&:rstrip).reject(&:empty?), exitstatus]
    rescue StandardError => e
      [false, ["#{e.class}: #{e.message}"], 1]
    end

    def child_timeout_s
      value = Integer(ENV.fetch("PUB4_CHECK_CHILD_TIMEOUT_S", CHILD_TIMEOUT_S.to_s), exception: false)
      value&.positive? ? value : CHILD_TIMEOUT_S
    end

    def suite_timeout_s(name)
      env_name = "PUB4_CHECK_TIMEOUT_#{name.upcase.gsub(/[^A-Z0-9]+/, "_")}"
      fallback = SUITE_TIMEOUTS.fetch(name, child_timeout_s)
      value = Integer(ENV.fetch(env_name, fallback.to_s), exception: false)
      value&.positive? ? value : fallback
    end

    # Use the same resource budget and critical floor as /fix. Check every volume
    # that can hold source, temporary artifacts or evidence; an unknown reading
    # blocks a new child instead of allowing it to exhaust the filesystem.
    def disk_state(paths)
      budget = Master::Fix::ResourceBudget.new(root: ROOT)
      readings = Array(paths).uniq.map { |path| budget.disk_free_gb_for(path) }
      return { free_gb: nil, critical: true } if readings.empty? || readings.any?(&:nil?)

      free_gb = readings.min
      { free_gb:, critical: budget.disk_critical?({ values: { disk_free_gb: free_gb } }) }
    rescue StandardError => e
      Master::Trace::Dmesg.status("check0", "disk state unreadable: #{e.class}: #{e.message}"[0, 200])
      { free_gb: nil, critical: true }
    end

    def disk_stop_reason(state, prefix:)
      free_gb = state[:free_gb]
      return "#{prefix}: free space could not be measured; refusing to run a child" if free_gb.nil?

      "#{prefix}: #{free_gb} GB free, below the configured critical disk floor"
    end

    def terminate_child_group(pid)
      Process.kill("TERM", -pid)
      sleep 2
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH
      nil
    end

    # Untracked files count: a stage that drops a new file in is a stage that
    # changed the tree, and much of the damage this chain attributes arrives so.
    def dirty
      out, status = Master::Io::Exec.capture2e("git", "status", "--porcelain=v1", "-z", chdir: ROOT)
      raise "check: git status failed: #{out.to_s.strip}" unless status.success?

      parse_dirty_paths(out)
    end

    def parse_dirty_paths(output)
      entries = output.to_s.split("\0")
      paths = []
      index = 0

      while index < entries.size
        entry = entries[index]
        break if entry.empty?

        status = entry[0, 2].to_s
        path = entry[3..].to_s
        paths << path unless path.empty?

        if status.match?(/[RC]/)
          index += 1
          renamed_path = entries[index].to_s
          paths << renamed_path unless renamed_path.empty?
        end
        index += 1
      end

      paths
    end

    # The instrument's own summary line, not the last line printed — the rule
    # tools/sweep.rb learned when design_baseline printed its verdict above its
    # detail and "last line" read a detail row as the verdict.
    def verdict(body)
      lines = Array(body).map(&:to_s)
      aggregate = lines.reverse.find { |line| line.match?(%r{\Achecks\d+ at rails: \d+ pass, \d+ fail\b}i) }
      return aggregate.strip if aggregate

      failed = lines.reverse.find do |line|
        line.match?(%r{\A[a-z][a-z_0-9]*:\s.*\b(?:failed|inconclusive|blocked|error)\b}i)
      end
      summary = lines.reverse.find { |line| line.match?(%r{\A[a-z][a-z_0-9]*:\s}) }
      (failed || summary || lines.last).to_s.strip
    end

    # The seam to the council's own diagnosis, not invented here.
    # Deliberation#failure_reason slugs each persona's failure and quorum_error
    # tallies them ("quorum not reached (2/26) — 24x insufficient_credits");
    # bin/check --ladder matches that on INCONCLUSIVE and --semantic-only returns 3 rather
    # than aborting. The reason arrives in the stage's verdict line, so this only
    # reads the status, and a richer predicate later changes this method alone.
    def classify(ok, exitstatus)
      return "ok" if ok
      return "skipped" if exitstatus == 3

      "failed"
    end

    def run_stage(stage, seen)
      unit = stage_unit(stage)
      Master::Trace::Dmesg.attach(
        unit, "check0",
        stage.mutates ? "#{stage.purpose}, writes" : stage.purpose
      )
      # A stage captures its output and can run for minutes; the heartbeat says which
      # stage is still running and for how long, in the stage's own unit.
      ok, body, exitstatus = CheckHeartbeat.around(stage.name, unit:) do |progress|
        stage.run.arity.zero? ? stage.run.call : stage.run.call(progress)
      end
      changed = dirty - seen
      state = classify(ok, exitstatus)
      state = "failed" if changed.any? && !stage.mutates
      summary = verdict(body)
      Master::Trace::Dmesg.status(unit, "#{state}, #{summary}")
      detail = body.last(state == "ok" ? 0 : 12)
      Master::Trace::Dmesg::Report.print(unit, detail.join("\n"), parent: "check0") unless detail.empty?
      announce_changed(unit, stage, changed)
      Result.new(stage: stage.name, state:, summary:, changed:, body:)
    end

    def stage_unit(stage)
      {
        "lexical" => "law0",
        "source" => "source0",
        "openbsd" => "openbsd0",
        "suites" => "suite0",
        "ratchets" => "ratchet0",
        "sprawl" => "sprawl0",
        "council" => "council0",
      }.fetch(stage.name) { "#{stage.name}0" }
    end

    def announce_foreign(foreign)
      if foreign.empty?
        Master::Trace::Dmesg.status("check0", "tree clean at start, all changes below are this run")
        return
      end

      Master::Trace::Dmesg.attach("foreign0", "check0", "#{foreign.size} pre-existing change(s), left untouched")
      foreign.first(20).each { |path| Master::Trace::Dmesg.status("foreign0", path) }
      more = foreign.size - 20
      Master::Trace::Dmesg.status("foreign0", "#{more} more") if more.positive?
    end

    def announce_changed(unit, stage, changed)
      return if changed.empty?

      label = stage.mutates ? "changed by #{stage.name}" : "changed by non-mutating stage"
      Master::Trace::Dmesg.status(unit, "#{changed.size} file(s), #{label}")
      changed.first(30).each do |path|
        detail = path.match?(GENERATED) ? "#{path}, generated, revert" : path
        Master::Trace::Dmesg.status(unit, detail)
      end
      more = changed.size - 30
      Master::Trace::Dmesg.status(unit, "#{more} more") if more.positive?
    end

    def summarise(results, foreign)
      changed = results.flat_map(&:changed)
      generated = changed.grep(GENERATED)
      clean = results.count { |result| result.state == "ok" }
      skipped = results.count { |result| result.state == "skipped" }
      failed = results.count { |result| result.state == "failed" }

      Master::Trace::Dmesg.status(
        "check0",
        "#{clean} clean, #{failed} failed, #{skipped} skipped, #{changed.size} changed, #{foreign.size} foreign",
      )
      results.select { |r| r.state == "skipped" }.each do |r|
        Master::Trace::Dmesg.status("check0", "#{r.stage}, skipped, #{r.summary}")
      end
      results.select { |r| r.state == "failed" }.each do |r|
        Master::Trace::Dmesg.status("check0", "#{r.stage}, failed, #{r.summary}")
      end
      generated.each do |path|
        Master::Trace::Dmesg.status("check0", "generated file rewritten, revert, #{path}")
      end

      return 1 if results.any? { |r| r.state == "failed" } || generated.any?
      return 3 if results.any? { |r| r.state == "skipped" }

      Master::Trace::Dmesg.status("check0", "clean")
      0
    end
  end
end
