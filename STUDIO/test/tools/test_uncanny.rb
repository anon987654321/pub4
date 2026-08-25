# frozen_string_literal: true

require_relative "../helper"
require "vips"
require "tmpdir"
require_relative "../../postpro/uncanny"

# A metric is worth exactly as much as the case where you already know the
# answer. These build images whose correct reading is not in doubt — a
# perfectly smooth field has no texture, a noisy one does — and assert the
# numbers move the right way.
#
# Without that, "texture=0.0082" is a number with no meaning, and a metric with
# no meaning is worse than none: it gets quoted.
class TestUncanny < Minitest::Test
  def with_images
    Dir.mktmpdir { |dir| yield dir }
  end

  def grey(dir, name, value: 140)
    path = File.join(dir, name)
    band = (Vips::Image.black(256, 256).cast(:float) + value).cast(:uchar)
    band.bandjoin([band, band]).write_to_file(path)
    path
  end

  def noisy(dir, name, sigma: 20, value: 140)
    path = File.join(dir, name)
    base = Vips::Image.black(256, 256).cast(:float) + value
    band = (base + Vips::Image.gaussnoise(256, 256, mean: 0, sigma: sigma)).cast(:uchar)
    band.bandjoin([band, band]).write_to_file(path)
    path
  end

  # The plastic-skin case, and the whole reason this file exists.
  def test_a_flat_field_has_no_texture_and_a_noisy_one_does
    with_images do |dir|
      flat = Postpro::Uncanny.read(grey(dir, "flat.png"))
      grainy = Postpro::Uncanny.read(noisy(dir, "grain.png"))

      assert_in_delta 0.0, flat.texture, 0.001, "a perfectly smooth field has no high-frequency energy"
      assert_operator grainy.texture, :>, flat.texture,
                      "noise is texture; if this does not rise the metric measures nothing"
    end
  end

  def test_more_noise_reads_as_more_texture
    with_images do |dir|
      light = Postpro::Uncanny.read(noisy(dir, "light.png", sigma: 6))
      heavy = Postpro::Uncanny.read(noisy(dir, "heavy.png", sigma: 40))

      assert_operator heavy.texture, :>, light.texture,
                      "the metric has to be monotonic in the thing it claims to measure"
    end
  end

  def test_a_blown_field_reads_as_clipping_and_a_midtone_does_not
    with_images do |dir|
      blown = Postpro::Uncanny.read(grey(dir, "blown.png", value: 255))
      midtone = Postpro::Uncanny.read(grey(dir, "mid.png", value: 128))

      assert_operator blown.clipping, :>, 50.0, "a pure white frame is mostly clipped"
      assert_in_delta 0.0, midtone.clipping, 0.001, "a midtone frame clips nothing"
    end
  end

  def test_reading_the_same_file_twice_gives_the_same_answer
    with_images do |dir|
      path = noisy(dir, "stable.png")

      assert_equal Postpro::Uncanny.read(path).to_h, Postpro::Uncanny.read(path).to_h,
                   "vips access mode has to allow re-reading; :sequential silently half-fails"
    end
  end

  def test_compare_reports_the_direction_of_each_change
    with_images do |dir|
      flat = grey(dir, "before.png")
      grainy = noisy(dir, "after.png")

      comparison = Postpro::Uncanny.compare(flat, grainy)

      assert_operator comparison[:texture_delta], :>, 0
      assert(Postpro::Uncanny.verdict(comparison).any? { |l| l.include?("texture rose") })
    end
  end

  # The verdict has to be able to say the grade made things worse, or it is
  # praise rather than measurement.
  def test_the_verdict_names_a_grade_that_removed_texture
    with_images do |dir|
      grainy = noisy(dir, "before.png")
      flat = grey(dir, "after.png")

      comparison = Postpro::Uncanny.compare(grainy, flat)

      assert(Postpro::Uncanny.verdict(comparison).any? { |l| l.include?("texture fell") },
             "a metric that only reports improvement is not a metric")
    end
  end
end
