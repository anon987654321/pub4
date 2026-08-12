# frozen_string_literal: true

# `already initialized constant ROOT` read as cosmetic noise in bin/check's
# output for as long as it had been there.
#
# It was the only thing standing between the security sweep and scanning the
# wrong tree. `rake test` requires MASTER/tools/security_sweep.rb and loads
# STUDIO/dilla/dilla.rb; both defined a bare top-level ROOT pointing at
# different directories, and Ruby resolves that by warning and letting the second
# assignment win. Load order decided whether `git ls-files` ran against pub4 or
# against a music folder, and the sweep printed "0 tracked secrets" either way.

require "minitest/autorun"
require_relative "../tools/constant_collisions"

class TestConstantCollisions < Minitest::Test
  def self.report = @report ||= Pub4::ConstantCollisions.run

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

  # The two files from the real incident must both still be in the set the gate
  # looks at, or it is green for the wrong reason.
  def test_both_files_from_the_original_collision_are_still_watched
    watched = Pub4::ConstantCollisions.files.select { |path| Pub4::ConstantCollisions.requirable[path] }

    assert watched.any? { |path| path.end_with?("MASTER/tools/security_sweep.rb") },
           "security_sweep.rb is no longer seen as requirable"
    assert watched.any? { |path| path.end_with?("STUDIO/dilla/dilla.rb") },
           "dilla.rb is no longer seen as requirable"
  end

  # And the detector must still call that pair a collision if it returns.
  def test_the_historical_collision_would_still_be_caught
    pair = Pub4::ConstantCollisions.files.select do |path|
      path.end_with?("MASTER/tools/security_sweep.rb", "STUDIO/dilla/dilla.rb")
    end
    defined_in = Pub4::ConstantCollisions.definitions(pair)

    assert_equal 1, defined_in["ROOT"].to_a.size,
                 "ROOT is back in more than one of the two files that collided"
    refute_empty defined_in["SWEEP_ROOT"],
                 "SWEEP_ROOT is gone — security_sweep.rb went back to a bare ROOT"
  end
end
