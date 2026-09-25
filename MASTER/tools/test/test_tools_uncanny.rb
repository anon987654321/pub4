# frozen_string_literal: true

require_relative "studio_helper"
require "vips"
require "tmpdir"
require_relative "../postpro/lib/uncanny"

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

  # LEVELS_OF_SCALE on the two failures it exists for. The same scene recorded
  # at full resolution holds detail in its finest octave; upscaled from half size
  # it holds almost none, because interpolation adds pixels and not detail.
  def test_an_upscaled_frame_has_lost_its_finest_octave
    native = Studio.octave_scene(512)
    upscaled = native.shrink(2, 2).resize(2.0, kernel: :linear).crop(0, 0, 512, 512)

    assert_operator Postpro::Uncanny.finest_octave(native), :>, 1.5,
                    "a frame at its own resolution carries detail in its finest octave"
    assert_operator Postpro::Uncanny.finest_octave(upscaled), :<, 0.7,
                    "interpolation adds pixels without adding detail"
  end

  def test_a_flat_frame_reads_zero_rather_than_dividing_by_it
    flat = (Vips::Image.black(128, 128) + 128).cast(:uchar)
    assert_equal 0.0, Postpro::Uncanny.finest_octave(flat)
  end

  # SQUINT_TEST against frames whose composition is not in doubt: a lit disc on a
  # dark field is structure a squint cannot erase, and fine noise is exactly the
  # detail a squint removes.
  def lit_disc
    size = 384
    field = Vips::Image.black(size, size).draw_circle(230, size / 2, size / 2, size / 4, fill: true) + 10
    (field + Vips::Image.gaussnoise(size, size, mean: 0, sigma: 6)).cast(:uchar)
  end

  def test_a_clear_subject_survives_the_squint_and_fine_detail_does_not
    noise = (Vips::Image.gaussnoise(384, 384, mean: 0, sigma: 40) + 128).cast(:uchar)

    assert_operator Postpro::Uncanny.squint_image(lit_disc), :>, 0.8,
                    "a lit disc on a dark field is structure a squint cannot erase"
    assert_operator Postpro::Uncanny.squint_image(noise), :<, 0.1,
                    "noise is detail, and detail is exactly what a squint removes"
  end

  def test_a_flat_frame_squints_to_zero_rather_than_dividing_by_it
    assert_equal 0.0, Postpro::Uncanny.squint_image((Vips::Image.black(64, 64) + 128).cast(:uchar))
  end
  def swatch(rgb) = (Vips::Image.black(16, 16) + rgb).cast(:uchar).copy(interpretation: :srgb)

  # Each named hue on its own pure sRGB swatch, and a grey that has none. Equal
  # hue bins read sRGB red as orange and blue as magenta, which is why the
  # boundaries are measured and why every name is asserted here.
  def test_a_pure_colour_lands_in_its_own_name_and_grey_is_neutral
    { "red" => [255, 0, 0], "orange" => [255, 128, 0], "yellow" => [255, 255, 0], "green" => [0, 200, 0],
      "cyan" => [0, 255, 255], "azure" => [0, 128, 255], "blue" => [0, 0, 255], "magenta" => [255, 0, 255],
      "rose" => [255, 0, 128], "neutral" => [128, 128, 128] }.each do |name, rgb|
      assert_in_delta 1.0, Postpro::Uncanny.palette(swatch(rgb)).fetch(name), 1e-9, "#{rgb.inspect} is not #{name}"
    end
  end

  def test_a_half_and_half_frame_splits_its_palette
    frame = swatch([255, 0, 0]).join(swatch([128, 128, 128]), :horizontal)
    palette = Postpro::Uncanny.palette(frame)

    assert_in_delta 0.5, palette["red"], 1e-9
    assert_in_delta 0.5, palette["neutral"], 1e-9
    assert_in_delta 1.0, palette.values.sum, 1e-9
  end
end
