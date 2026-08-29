# frozen_string_literal: true

require_relative "studio_helper"
require "vips"
require "tmpdir"
require_relative "../postpro/rescue"

# "Make any bad photo look good", with "although I realize that's a stretch"
# attached. The stretch is not uniform, and that is the whole design:
# PHOTOGRAPHY.md splits a photograph into four layers that fail independently,
# and exactly one of them is a grade's to fix.
#
# So the tests that matter most here are the ones asserting what it REFUSES. A
# rescue tool that quietly tries everything and reports success is lying about
# three layers out of four, and the lie is expensive: it costs a reshoot that
# would have worked.
class TestRescue < Minitest::Test
  def flat(dir, value: 140)
    path = File.join(dir, "flat.jpg")
    band = (Vips::Image.black(256, 256).cast(:float) + value).cast(:uchar)
    band.bandjoin([band, band]).write_to_file("#{path}[Q=95]")
    path
  end

  def blown(dir)
    path = File.join(dir, "blown.jpg")
    band = (Vips::Image.xyz(256, 256)[0] * (420.0 / 256)).cast(:uchar)
    band.bandjoin([band, band]).write_to_file("#{path}[Q=95]")
    path
  end

  def cast_image(dir)
    path = File.join(dir, "cast.jpg")
    r = (Vips::Image.black(256, 256).cast(:float) + 180).cast(:uchar)
    g = (Vips::Image.black(256, 256).cast(:float) + 140).cast(:uchar)
    b = (Vips::Image.black(256, 256).cast(:float) + 90).cast(:uchar)
    r.bandjoin([g, b]).write_to_file("#{path}[Q=95]")
    path
  end

  def codes(path) = Postpro::Rescue.diagnose(path).map(&:code)

  # The phone-filter / diffusion case, and the one thing here that genuinely
  # rescues a picture.
  def test_a_smoothed_image_is_diagnosed_as_plastic_and_offered_grain
    Dir.mktmpdir do |dir|
      findings = Postpro::Rescue.diagnose(flat(dir))
      plastic = findings.find { |f| f.code == :plastic }

      assert plastic, "a perfectly smooth frame has to read as over-smoothed"
      assert_equal :fixable, plastic.severity
      assert_includes plastic.remedy, "grain"
    end
  end

  # The one that must never be reported as fixed.
  def test_blown_highlights_are_reported_as_unfixable
    Dir.mktmpdir do |dir|
      blown_finding = Postpro::Rescue.diagnose(blown(dir)).find { |f| f.code == :blown }

      assert blown_finding, "a frame that is 40% clipped has to be noticed"
      assert_equal :unfixable, blown_finding.severity,
                   "a grade cannot recover what was never recorded, and saying it can is the lie"
    end
  end

  def test_a_colour_cast_is_detected
    Dir.mktmpdir { |dir| assert_includes codes(cast_image(dir)), :cast }
  end

  def test_a_neutral_frame_is_not_reported_as_cast
    Dir.mktmpdir do |dir|
      refute_includes codes(flat(dir)), :cast,
                      "a grey frame has no cast; reporting one is noise that trains people to ignore this"
    end
  end

  # Said every time, not only when something is detected — their absence from a
  # report would read as their absence from the photograph, and neither is
  # measurable from pixels.
  def test_the_unreachable_layers_are_always_named
    Dir.mktmpdir do |dir|
      report = Postpro::Rescue.report(Postpro::Rescue.diagnose(flat(dir))).join(" ")

      assert_includes report, "geometry"
      assert_includes report, "reshoot"
      assert_includes report, "expression"
      assert_includes report, "focus"
    end
  end

  def test_the_unreachable_layers_are_named_even_when_nothing_is_wrong
    report = Postpro::Rescue.report([]).join(" ")

    assert_includes report, "nothing measurable is wrong"
    assert_includes report, "geometry",
                    "a clean optical layer does not make the other three reachable"
  end

  # The rescue applies an existing preset rather than a bespoke chain, so a
  # rescued photograph and a graded one are the same look.
  def test_the_preset_chosen_matches_the_diagnosis
    assert_equal "portrait", Postpro::Rescue.preset_for([Postpro::Rescue::Finding.new(code: :plastic)])
    assert_equal "reportage", Postpro::Rescue.preset_for([Postpro::Rescue::Finding.new(code: :flat)])
    assert_nil Postpro::Rescue.preset_for([]), "nothing wrong means nothing applied"
  end

  def test_a_frame_that_is_both_flat_and_plastic_gets_the_combined_preset
    findings = [Postpro::Rescue::Finding.new(code: :flat), Postpro::Rescue::Finding.new(code: :plastic)]

    assert_equal "quality_uplift", Postpro::Rescue.preset_for(findings)
  end
end
