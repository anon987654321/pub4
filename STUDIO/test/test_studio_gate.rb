# frozen_string_literal: true

require_relative "helper"
require "open3"
require "rbconfig"
require "digest"
require "tmpdir"
require_relative "../gate.rb"

# The gate is the only thing standing between MASTER's fix loop and a broken
# STUDIO, and it has one property nothing else in this repo has: it checks
# itself, by running a second instance over a tree broken on purpose. What it
# does not check is its own configuration -- TREES, VENDORED and the entry list
# are data, and a glob that matches nothing passes every check in the file
# while covering nothing.
class TestStudioGate < Minitest::Test
  GATE = Deploy::StudioGate

  def gate = @gate ||= GATE.new

  # --- the trees are configured, not merely declared ----------------------

  def test_every_declared_tree_matches_real_files
    GATE::TREES.each do |tree|
      matches = Dir[File.join(GATE::ROOT, tree[:glob])].reject { |p| p.match?(GATE::VENDORED) }
      refute_empty matches, "#{tree[:name]}'s glob #{tree[:glob]} matches nothing, so it checks nothing"
    end
  end

  def test_every_declared_entry_point_is_on_disk_and_guarded
    GATE::TREES.each do |tree|
      entry = tree[:entry]
      next unless entry

      path = File.join(GATE::ROOT, entry)
      assert File.file?(path), "#{tree[:name]} names an entry that does not exist: #{entry}"
      assert_match(/__FILE__\s*==\s*(\$PROGRAM_NAME|\$0)/, File.read(path),
                   "#{entry} runs its CLI at load, so nothing past parse can check #{tree[:name]}")
    end
  end

  def test_every_tree_names_who_owns_it
    GATE::TREES.each do |tree|
      refute_empty tree[:owner].to_s.strip, "#{tree[:name]} has no owner, so a stray file there has no home"
      refute_empty tree[:name].to_s.strip
    end
  end

  def test_the_trees_do_not_overlap
    owners = Hash.new { |h, k| h[k] = [] }
    gate.source_files.each do |path|
      GATE::TREES.each do |tree|
        owners[path] << tree[:name] if File.fnmatch?(File.join(GATE::ROOT, tree[:glob]), path, File::FNM_PATHNAME)
      end
    end
    unowned = owners.select { |_, names| names.empty? }
    doubled = owners.select { |_, names| names.size > 1 }

    assert_empty unowned, "these files belong to no declared tree: #{unowned.keys.inspect}"
    assert_empty doubled, "these files are claimed by two trees, so they are parsed twice: #{doubled.keys.inspect}"
  end

  # --- the vendored filter ------------------------------------------------

  def test_vendored_directories_are_excluded
    %w[
      /STUDIO/dilla/scratch/venv-demucs/lib/python3.14/site-packages/x.rb
      /STUDIO/dilla/renders/x.rb
      /STUDIO/dilla/samples/x.rb
      /STUDIO/postpro/node_modules/x.rb
    ].each { |path| assert_match GATE::VENDORED, path, "#{path} is not first-party and would be parsed" }
  end

  # The filter is a regex over the whole path, so a first-party directory whose
  # name merely contains one of those words would vanish from every check.
  def test_first_party_source_survives_the_filter
    %w[
      /STUDIO/dilla/dilla.rb
      /STUDIO/dilla/lib/engine/chord_theory.rb
      /STUDIO/postpro/postpro.rb
      /STUDIO/repligen/repligen.rb
      /STUDIO/gate.rb
    ].each { |path| refute_match GATE::VENDORED, path, "#{path} is first-party and is being skipped" }
  end

  def test_the_corpus_is_the_first_party_tree_and_nothing_else
    files = gate.source_files

    refute_empty files
    assert_includes files, File.join(GATE::ROOT, "dilla", "dilla.rb")
    assert_includes files, File.join(GATE::ROOT, "gate.rb")
    assert_empty files.select { |p| p.match?(GATE::VENDORED) }
    assert_equal files.sort, files, "the corpus is unordered, so failures come out in a different order each run"
  end

  # A dilla engine part must be in the gate's corpus, or the parse check runs
  # over a set that excludes the files an autofix is most likely to break --
  # which is exactly what happened before engine_sources.rb existed.
  def test_the_corpus_reaches_every_engine_part
    require_relative "../dilla/lib/engine_sources"
    missing = DillaSources.all - gate.source_files

    assert_empty missing, "the gate parses a corpus that excludes #{missing.size} engine file(s)"
  end

  # --- the self-check -----------------------------------------------------

  def test_the_self_check_predicts_each_class_of_finding
    assert_equal %w[studio\ inventory: studio\ load: studio\ parse:].sort,
                 GATE::PREDICTED_FINDINGS.keys.sort,
                 "a prediction was added or dropped without the fixture that produces it"
    GATE::PREDICTED_FINDINGS.each_value { |why| refute_empty why.to_s.strip }
  end

  # The prediction is registered before the fixture is built; this observes it.
  # If the gate stops reporting one of the three, its pass line is decoration.
  def test_the_gate_still_fires_on_a_deliberately_broken_tree
    observed = gate.send(:broken_tree_findings)

    GATE::PREDICTED_FINDINGS.each do |marker, defect|
      assert observed.any? { |finding| finding.include?(marker) },
             "the gate no longer reports #{defect}; observed: #{observed.inspect}"
    end
  end

  def test_a_probe_timeout_is_bounded_and_finite
    assert_operator GATE::PROBE_TIMEOUT, :>, 0
    assert_operator GATE::PROBE_TIMEOUT, :<=, 600, "a probe that can run ten minutes is not a gate"
  end

  # --- the gate over the real tree ---------------------------------------

  def test_the_real_tree_passes_its_own_gate
    result = GATE.new.run

    assert_empty result.failures, "STUDIO is broken:\n  #{result.failures.join("\n  ")}"
    # A gate that measured nothing and a gate that passed print the same line
    # unless the count is asserted; GateResult carries it for exactly this.
    assert_operator result.checks_ran, :>, 0, "a gate that checked nothing cannot have passed"
    refute result.measured_nothing?, result.nothing_measured_reason.to_s
  end

# The suite has to leave dilla's state exactly as it found it.
#
# This is tested end to end, in a real subprocess minitest run, because the way
# it broke was invisible to every other kind of check. The restoration existed,
# was correct, was called, and ran at the wrong moment:
#
#   test/helper.rb requires minitest/autorun, which registers an at_exit that
#   RUNS THE SUITE. `at_exit` handlers run LIFO, so an at_exit registered after
#   that one fires FIRST -- before any test has run. The restore was therefore
#   putting back files nothing had touched yet, every run, for its whole life,
#   while the suite went on rewriting them.
#
# Nothing failed. The code was present and the hook was live; only its ORDER was
# wrong, and order is not visible in a diff, a parse check, or a unit test of
# restore_engine_state! -- which passes perfectly when called directly.
#
# It was masked further by a second restore hook in test_engine_probes.rb, added
# as a Minitest.after_run block, which ran at the right time and did the work.
# Removing that duplicate -- correct on its own terms, since the two snapshotted
# the same files at different moments and fought at exit -- is what exposed this.
#
# So the guard is behavioural: dirty a real state file inside a real test run and
# check it comes back. A source-grep for "Minitest.after_run" would pass on a
# hook registered in a file nobody loads.
  TARGET = File.expand_path("../dilla/project/session.json", __dir__)

  def test_a_test_run_that_dirties_engine_state_restores_it
    skip "no session state on this machine yet" unless File.file?(TARGET)

    original = File.binread(TARGET)
    Dir.mktmpdir do |dir|
      # A minimal suite that loads STUDIO's helper -- which is what installs the
      # restoration -- and then writes rubbish into a tracked state file from
      # inside a test, which is exactly what loading the engine does.
      probe = File.join(dir, "test_dirty.rb")
      File.write(probe, <<~RUBY)
        require #{File.expand_path("helper.rb", __dir__).inspect}
        class TestDirty < Minitest::Test
          def test_writes_engine_state
            File.binwrite(#{TARGET.inspect}, "{\\"dirtied_by\\": \\"the restoration guard\\"}")
            assert true
          end
        end
      RUBY
      out, err, status = Open3.capture3(RbConfig.ruby, probe)

      assert status.success?, "the probe suite failed: #{err}#{out}"
      assert_equal original, File.binread(TARGET),
                   "a test run dirtied #{File.basename(TARGET)} and the suite did not put it back — " \
                   "check that test/helper.rb registers restore_engine_state! with Minitest.after_run " \
                   "and not with a bare at_exit, which runs BEFORE the tests"
    end
  ensure
    # Whatever the assertion decided, this tree is not ours to leave broken.
    File.binwrite(TARGET, original) if original && File.binread(TARGET) != original
  end

  # The ordering trap, stated as its own check. The behavioural test above is the
  # real guard; this one names the cause, so a failure says what to fix rather
  # than only that something is wrong.
  def test_the_restore_is_registered_where_it_runs_after_the_suite
    source = File.read(File.expand_path("helper.rb", __dir__))

    assert_match(/Minitest\.after_run\s*\{\s*Studio\.restore_engine_state!/, source,
                 "restore_engine_state! must be registered with Minitest.after_run — a bare at_exit " \
                 "is registered after minitest/autorun's and therefore runs before the tests")
  end

  # One snapshot, taken before the engine can write anything. Two hooks holding
  # snapshots from different moments is what the probe file used to do, and at
  # exit the later snapshot won and undid the earlier one's work.
  def test_only_one_snapshot_of_engine_state_exists
    # Comments stripped first, which is not fussiness -- the first version of
    # this test failed on test_engine_probes.rb because the note explaining why
    # its hook was REMOVED mentions Minitest.after_run by name. A ratchet that
    # reads prose reports the documentation of a fix as the fix's absence, and
    # dilla's own wiring ratchets strip comments for exactly this reason.
    duplicates = Dir[File.expand_path("dilla/test_*.rb", __dir__)].select do |path|
      File.read(path).gsub(/^\s*#(?!\{).*$/, "").match?(/Minitest\.after_run|STATE_AT_LOAD/)
    end

    assert_empty duplicates.map { |p| File.basename(p) },
                 "a second state-restoration hook has come back; test/helper.rb owns this"
  end

end