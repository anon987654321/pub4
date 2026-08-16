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

    assert_includes found.first, "thing: 3 files"
  end

  def test_three_files_that_never_reference_each_other_are_not_a_family
    write("solo_a.rb", "def solo_a = 1\n")
    write("solo_b.rb", "def solo_b = 2\n")
    write("solo_c.rb", "def solo_c = 3\n")

    assert_equal 0, Pub4::Cohesion.run(@tmp), "a shared prefix alone is naming, not cohesion"
  end

  # The discriminator that keeps it off MASTER's own tree: a file declaring a
  # module already has the boundary a merge would be giving it.
  def test_namespaced_files_are_left_alone
    flat_family
    %w[thing_a thing_b thing_c].each_with_index do |n, i|
      write("#{n}.rb", "module Thing#{i}\n  ALPHA = 1\n  def self.run = 1\nend\n")
    end

    assert_equal 0, Pub4::Cohesion.run(@tmp)
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
    plan = Pub4::Cohesion.plan_for("thing", Dir.glob(File.join(@tmp, "thing_*.rb")), %w[thing_c thing_a thing_b])

    assert_equal "thing_b", plan[:take_position_of]
    assert_equal %w[thing_c.rb thing_a.rb thing_b.rb], plan[:files]
  end

  def test_it_emits_a_plan_rather_than_a_patch
    flat_family
    plan = Pub4::Cohesion.plan_for("thing", Dir.glob(File.join(@tmp, "thing_*.rb")), [])

    refute_empty plan[:check], "a merge crosses files and load order; the checks are the deliverable"
    assert_equal 4, plan[:methods], "one def in thing_a and thing_c, two in thing_b"
  end
end
