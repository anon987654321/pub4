# frozen_string_literal: true

require_relative "helper"
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
end
