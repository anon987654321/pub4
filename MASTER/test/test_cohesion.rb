# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../tools/cohesion"

# The rule MASTER did not have. SMALL_FILES, NO_GOD_CLASS and INTEGRATED_SYSTEMS
# all say "split further"; nothing said "these are one thing", so no scan ever
# proposed a merge. What it must not do is fire on files that merely read alike.
class CohesionTest < Minitest::Test
  def setup = @tmp = Dir.mktmpdir("cohesion")
  def teardown = FileUtils.remove_entry(@tmp)

  def write(name, body) = File.write(File.join(@tmp, name), body)

  def families = Pub4::Cohesion.families(@tmp)

  def flat_family
    write("thing_a.rb", "ALPHA = 1\ndef thing_a_run = thing_b_help\n")
    write("thing_b.rb", "def thing_b_help = ALPHA\ndef thing_b_other = thing_c_pick\n")
    write("thing_c.rb", "def thing_c_pick = thing_a_run\n")
  end

  def test_a_flat_family_that_calls_itself_is_one_concept
    flat_family
    found = capture_io { Pub4::Cohesion.run(@tmp) }

    assert_includes found.first, "thing [merge, by prefix]: 3 files"
  end

  def test_three_files_that_never_reference_each_other_are_not_a_family
    write("solo_a.rb", "def solo_a = 1\n")
    write("solo_b.rb", "def solo_b = 2\n")
    write("solo_c.rb", "def solo_c = 3\n")

    assert_equal 0, Pub4::Cohesion.run(@tmp), "a shared prefix alone is naming, not cohesion"
  end

  # This asserted 0 — "a file declaring a module already has the boundary a merge
  # would be giving it" — and that reasoning is what kept the tool off MASTER's
  # own tree entirely, because every file under lib/ declares one. It is half
  # right: under Zeitwerk a path IS a constant name, so those files genuinely
  # cannot be poured into each other. They can be shelved. So a namespaced family
  # gets a regroup plan, and never a merge.
  def test_namespaced_files_get_a_regroup_and_never_a_merge
    flat_family
    %w[thing_a thing_b thing_c].each_with_index do |n, i|
      write("#{n}.rb", "module Thing#{i}\n  ALPHA = 1\n  def self.run = 1\nend\n")
    end

    plans = Pub4::Cohesion.plans_for(@tmp)

    assert_equal 1, plans.size
    assert_equal "regroup", plans.first[:plan], "Zeitwerk refuses two constants at one path"
  end

  def test_two_files_are_below_the_family_floor
    write("pair_a.rb", "def pair_a = pair_b\n")
    write("pair_b.rb", "def pair_b = pair_a\n")

    assert_equal 0, Pub4::Cohesion.run(@tmp)
  end

  # The plan names the merge site by load order, not alphabetically: the latest
  # member, so anything an earlier member reads at load time is already defined.
  def test_the_plan_merges_into_the_latest_member_of_the_manifest
    flat_family
    plan = Pub4::Cohesion.merge_plan("thing", Dir.glob(File.join(@tmp, "thing_*.rb")), :prefix, %w[thing_c thing_a thing_b])

    assert_equal "thing_b", plan[:take_position_of]
    assert_equal %w[thing_c.rb thing_a.rb thing_b.rb], plan[:files]
  end

  def test_it_emits_a_plan_rather_than_a_patch
    flat_family
    plan = Pub4::Cohesion.merge_plan("thing", Dir.glob(File.join(@tmp, "thing_*.rb")), :prefix, [])

    refute_empty plan[:check], "a merge crosses files and load order; the checks are the deliverable"
    assert_equal 4, plan[:methods], "one def in thing_a and thing_c, two in thing_b"
  end

  # ---- the suffix half ------------------------------------------------------
  #
  # Grouping on `split("_").first` alone read prefix families and nothing else.
  # dilla names families by prefix (render_seed, render_techno); MASTER names
  # them by suffix (sandbox_policy, workflow_policy). So the tool was blind to
  # the shape of the tree it lives in — "nothing to merge" across lib/ground,
  # lib/review, lib/cli and lib/voice, 325 files, and the matcher's fault.

  def namespaced(const) = "module Master\n  module Ground\n    class #{const}\n      def call = :x\n    end\n  end\nend\n"

  def policy_family
    write("sandbox_policy.rb", namespaced("SandboxPolicy"))
    write("subagent_policy.rb", namespaced("SubagentPolicy"))
    write("workflow_policy.rb", namespaced("WorkflowPolicy"))
  end

  def test_a_suffix_family_is_found
    policy_family

    assert_includes families.map { |name, _, kind| [name, kind] }, ["policy", :suffix]
  end

  def test_a_suffix_family_regroups_into_a_subdirectory
    policy_family
    plan = Pub4::Cohesion.plans_for(@tmp).first

    assert_equal "regroup", plan[:plan]
    assert_includes plan[:moves].map { |m| m[:to] }, "policy/sandbox.rb"
    assert_includes plan[:moves].map { |m| m[:constant] }, "SandboxPolicy -> Policy::Sandbox"
  end

  def test_the_member_named_for_the_family_becomes_the_parent
    policy_family
    write("policy.rb", namespaced("Policy"))
    plan = Pub4::Cohesion.plans_for(@tmp).first

    assert_equal "policy.rb", plan[:parent]
    assert_equal 3, plan[:moves].size, "the parent is not moved into its own shelf"
  end

  def test_without_a_parent_the_plan_says_one_must_be_created
    policy_family
    plan = Pub4::Cohesion.plans_for(@tmp).first

    assert_match(/must be created/, plan[:parent])
  end

  # ---- the filter that makes the suffix half safe ---------------------------
  #
  # Rails puts *_controller.rb in app/controllers/ by rule. The first repo-wide
  # run found 64 families and most were exactly that: eight controllers,
  # twenty-one reflexes, six helpers, four jobs. A shelf named for the room it
  # stands in is not a shelf.

  def in_dir(*segments)
    dir = File.join(@tmp, *segments)
    FileUtils.mkdir_p(dir)
    %w[posts users pages].each { |n| File.write(File.join(dir, "#{n}_controller.rb"), namespaced("#{n.capitalize}Controller")) }
    dir
  end

  def test_a_suffix_the_directory_declares_is_not_a_family
    assert_empty Pub4::Cohesion.families(in_dir("controllers"))
  end

  # The shared engine nests app/controllers/shared/, so the type is declared by
  # the grandparent and a basename-only test still matched every controller.
  def test_the_declaring_directory_may_be_the_grandparent
    assert_empty Pub4::Cohesion.families(in_dir("controllers", "shared"))
  end

  # rules/ holding *_rules.rb: the key is already plural, so singularising the
  # directory segment alone missed it.
  def test_a_plural_directory_matching_a_plural_suffix_is_conventional
    dir = File.join(@tmp, "rules")
    FileUtils.mkdir_p(dir)
    %w[web js ruby].each { |n| File.write(File.join(dir, "#{n}_rules.rb"), namespaced("#{n.capitalize}Rules")) }

    assert_empty Pub4::Cohesion.families(dir)
  end

  def test_a_prefix_family_is_still_found_after_all_that
    write("render_seed.rb", "def render_seed = render_techno\n")
    write("render_techno.rb", "def render_techno = render_analog\n")
    write("render_analog.rb", "def render_analog = render_seed\n")

    assert_equal "merge", Pub4::Cohesion.plans_for(@tmp).first[:plan]
  end

  # ---- the census -----------------------------------------------------------

  def test_the_census_roots_all_exist
    missing = Pub4::Cohesion::ROOTS.reject { |r| Dir.exist?(File.join(Pub4::Cohesion::REPO, r)) }

    assert_empty missing, "a root that does not exist counts nothing and reads as clean"
  end

  def test_the_census_ceiling_is_recorded
    assert_kind_of Integer, YAML.safe_load_file(Pub4::Cohesion::CENSUS).fetch("families")
  end
end
