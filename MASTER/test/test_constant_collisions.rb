# frozen_string_literal: true

# The former Dilla/secret-sweep ROOT collision is fixed. Keep a regression for
# the detector itself and for the live security-sweep boundary, not a test that
# expects the deleted engine file to keep defining a colliding constant.

require "minitest/autorun"
require "tmpdir"
require_relative "../tools/constant_collisions"

class TestConstantCollisions < Minitest::Test
  def self.report = @report ||= Operator::ConstantCollisions.run

  def setup
    @report = self.class.report
  end

  def test_no_two_requirable_files_define_the_same_top_level_constant
    collisions = @report["findings"].map { |row| "#{row['constant']}: #{row['files'].join(', ')}" }

    assert_empty collisions,
                 "two files that can be loaded into one process define the same top-level " \
                 "constant. The second assignment wins and the first file silently reads the " \
                 "other's value — namespace one of them:\n  #{collisions.join("\n  ")}"
  end

  # A detector that has stopped finding files reports clean forever, and the
  # requirable set is the half most likely to silently empty.
  def test_the_detector_still_sees_the_tree
    assert_operator @report["scanned"], :>, 1500, "only #{@report['scanned']} Ruby files seen"
    assert_operator @report["requirable"], :>, 200,
                    "only #{@report['requirable']} requirable files — the require_relative walk broke"
  end

  def test_the_security_sweep_remains_in_the_requirable_set
    watched = Operator::ConstantCollisions.files.select { |path| Operator::ConstantCollisions.requirable[path] }

    assert watched.any? { |path| path.end_with?("MASTER/tools/security_sweep.rb") },
           "security_sweep.rb is no longer seen as requirable"
  end

  def test_the_live_security_sweep_uses_its_scoped_constant
    path = File.join(Operator::ConstantCollisions::ROOT, "MASTER/tools/security_sweep.rb")
    source = File.read(path)

    assert_match(/^SWEEP_ROOT\s*=/, source)
    refute_match(/^ROOT\s*=/, source)
  end

  def test_the_detector_reports_duplicate_top_level_constants
    Dir.mktmpdir("constant-collisions") do |dir|
      first = File.join(dir, "first.rb")
      second = File.join(dir, "second.rb")
      File.write(first, "ROOT = :first\n")
      File.write(second, "ROOT = :second\n")

      defined_in = Operator::ConstantCollisions.definitions([first, second])

      assert_equal 2, defined_in["ROOT"].size
    end
  end
end
