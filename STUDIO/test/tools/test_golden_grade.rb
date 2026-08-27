# frozen_string_literal: true

require_relative "../helper"
require "vips"
require "tmpdir"
require "open3"
require "rbconfig"
require "digest"
require_relative "../../postpro/uncanny"

# What a grade DOES, not merely that it did something.
#
# postpro's own suite already has test_every_effect_changes_at_least_one_pixel,
# which was written because effects were found that ran, did not crash, and
# changed nothing. That catches the dead effect and cannot catch the wrong one:
# an effect can transform every pixel and be catastrophically wrong.
#
# So these run real presets over fixtures whose correct behaviour is not in
# doubt, and assert direction and bounds on the measurements in
# postpro/uncanny.rb. A highlight ramp must not come back clipped. A flat field
# must come back with more texture than it went in with, because grain is what
# the portrait preset is for.
#
# Fixtures are GENERATED, not committed. Deterministic from vips primitives, so
# there is no binary in git to go stale, nothing to regenerate by hand, and
# nobody has to wonder whether the checked-in png matches the code that made it.
#
# Tolerances rather than hashes, deliberately. Runs are byte-identical under
# POSTPRO_SEED — asserted below, because everything else here depends on it —
# so a hash would work and would be the wrong tool: it says a curve changed
# without saying whether highlights now clip, which is the only part anyone
# needs to decide about.
class TestGoldenGrade < Minitest::Test
  POSTPRO = File.expand_path("../../postpro/postpro.rb", __dir__)
  SEED = "42"

  # One preset per family rather than all 57: these shell out and each costs
  # about a second. The families differ in what they do to tone, which is what
  # is being asserted.
  PRESETS = %w[portrait cinematic silver_gelatin bleached].freeze

  def grade(input, preset, dir)
    output = File.join(dir, "#{preset}-#{File.basename(input)}")
    _out, status = Open3.capture2e(
      { "POSTPRO_SEED" => SEED, "DILLA_QUIET" => "1" },
      RbConfig.ruby, POSTPRO, "--input", input, "--output", output, "--preset", preset
    )
    assert status.success?, "postpro --preset #{preset} failed on #{File.basename(input)}"
    output
  end

  # A smooth mid-grey field. The plastic-skin case: no texture at all.
  def flat_field(dir, value: 140)
    path = File.join(dir, "flat.jpg")
    band = (Vips::Image.black(320, 320).cast(:float) + value).cast(:uchar)
    band.bandjoin([band, band]).write_to_file("#{path}[Q=95]")
    path
  end

  # A horizontal ramp into near-white. Nothing here is clipped going in, so
  # the grade clipped anything clipped coming out.
  def highlight_ramp(dir)
    path = File.join(dir, "ramp.jpg")
    ramp = Vips::Image.xyz(320, 320)[0] * (250.0 / 320)
    band = ramp.cast(:uchar)
    band.bandjoin([band, band]).write_to_file("#{path}[Q=95]")
    path
  end

  def test_the_fixtures_are_what_they_claim_to_be
    Dir.mktmpdir do |dir|
      flat = Postpro::Uncanny.read(flat_field(dir))
      ramp = Postpro::Uncanny.read(highlight_ramp(dir))

      assert_in_delta 0.0, flat.texture, 0.005, "the flat fixture has to be flat or it tests nothing"
      assert_in_delta 0.0, ramp.clipping, 0.01, "the ramp fixture must not arrive already clipped"
    end
  end

  # The claim that made `portrait` the default grade.
  def test_the_portrait_preset_puts_texture_into_a_flat_field
    Dir.mktmpdir do |dir|
      input = flat_field(dir)
      before = Postpro::Uncanny.read(input)
      after = Postpro::Uncanny.read(grade(input, "portrait", dir))

      assert_operator after.texture, :>, before.texture,
                      "portrait carries grain; a flat field must come back with more high-frequency " \
                      "energy than it went in with, or the anti-plastic claim is empty"
    end
  end

  # The failure a grade can cause that no amount of grain excuses.
  def test_no_preset_blows_a_highlight_ramp_that_arrived_intact
    Dir.mktmpdir do |dir|
      input = highlight_ramp(dir)

      PRESETS.each do |preset|
        after = Postpro::Uncanny.read(grade(input, preset, dir))

        assert_operator after.clipping, :<, 5.0,
                        "#{preset} clipped #{after.clipping.round(2)}% of a ramp that arrived with none — " \
                        "a grade may compress highlights, it may not destroy them"
      end
    end
  end

  # A grade that leaves the picture where it found it is a grade nobody needs.
  def test_every_preset_moves_at_least_one_measurement
    Dir.mktmpdir do |dir|
      input = flat_field(dir)
      before = Postpro::Uncanny.read(input)

      PRESETS.each do |preset|
        after = Postpro::Uncanny.read(grade(input, preset, dir))
        moved = %i[texture specular_spread clipping tonal_range].any? do |metric|
          (after.public_send(metric) - before.public_send(metric)).abs > 1e-6
        end

        assert moved, "#{preset} left every measurement where it found it"
      end
    end
  end

  # Everything above depends on this. Without it the tolerances would have to be
  # loose enough to be meaningless, and a real regression would fit inside them.
  #
  # Asserted on the FILE, not on the measurements. The first version compared
  # readings and failed at the tenth decimal — 0.004970436552810456 against
  # 0.004970436559582958 — on two runs whose output bytes were identical. vips
  # reduces across threads and the summation order is not fixed, so the grade
  # was reproducible and the instrument was not. Hashing the output asks the
  # question that was meant.
  def test_a_seeded_grade_is_reproducible
    Dir.mktmpdir do |dir|
      input = flat_field(dir)
      first = grade(input, "portrait", File.join(dir, "a").tap { |path| Dir.mkdir(path) })
      second = grade(input, "portrait", File.join(dir, "b").tap { |path| Dir.mkdir(path) })

      assert_equal Digest::SHA256.file(first).hexdigest, Digest::SHA256.file(second).hexdigest,
                   "POSTPRO_SEED has to pin the grain, or none of the assertions above mean anything"
    end
  end

  # And the measurements have to agree to a usable precision, or the tolerances
  # in the other tests are picked out of the air.
  def test_the_measurements_agree_between_identical_runs
    Dir.mktmpdir do |dir|
      input = flat_field(dir)
      first = Postpro::Uncanny.read(grade(input, "portrait", File.join(dir, "a").tap { |p| Dir.mkdir(p) }))
      second = Postpro::Uncanny.read(grade(input, "portrait", File.join(dir, "b").tap { |p| Dir.mkdir(p) }))

      %i[texture specular_spread clipping tonal_range].each do |metric|
        assert_in_delta first.public_send(metric), second.public_send(metric), 1e-6,
                        "#{metric} varies between identical runs by more than the tolerances here assume"
      end
    end
  end

  # The other half of the flat-field case, and the half that was missing.
  #
  # Every test above feeds the grade something with nothing in it — a flat field
  # or a clean ramp — which is the generated-image case the presets were tuned
  # against. Against that input the chain is purely additive and cannot be
  # caught taking anything away, because there is nothing there to take.
  #
  # A photograph arrives with texture and contrast already in it, and against
  # that input the same chain was subtractive: measured on real photographs it
  # removed up to 57% of the picture's micro-detail in a single step and 0.09 of
  # its tonal range overall, coming out milky and flat. Three separate defects
  # produced it — a blurred base in dir_coupler, a preserve_blacks branch that
  # lifted blacks 5.4x harder than not preserving them, and a defocus whose
  # sigma floors ignored any request to soften less.
  #
  # So: mid-grey with real high-frequency content in it, and gaussian noise
  # rather than a photograph because fixtures here are generated and nothing
  # binary belongs in git.
  def textured_field(dir, value: 128, sigma: 24)
    path = File.join(dir, "textured.png")
    base = Vips::Image.black(320, 320).cast(:float) + value
    noise = Vips::Image.gaussnoise(320, 320, mean: 0, sigma: sigma, seed: 7)
    band = (base + noise).cast(:uchar)
    # PNG, not JPEG: this fixture exists to carry high-frequency detail and JPEG
    # is a low-pass filter, so a jpg fixture would measure the codec.
    band.bandjoin([band, band]).write_to_file(path)
    path
  end

  def test_the_textured_fixture_is_what_it_claims_to_be
    Dir.mktmpdir do |dir|
      texture = Postpro::Uncanny.read(textured_field(dir)).texture

      assert_operator texture, :>, 0.015,
                      "the fixture has to carry more texture than a photograph's low end (0.015) " \
                      "or it cannot detect a grade that strips it"
    end
  end

  def test_the_grade_does_not_strip_texture_from_a_picture_that_arrived_with_it
    Dir.mktmpdir do |dir|
      input = textured_field(dir)
      before = Postpro::Uncanny.read(input).texture
      after = Postpro::Uncanny.read(grade(input, "portrait", dir)).texture

      assert_operator after, :>, before * 0.75,
                      "portrait cut texture from #{before.round(4)} to #{after.round(4)} — a grade whose " \
                      "whole claim is putting micro-detail back may not be the thing removing it"
    end
  end

  # shadow_lift as a target rather than an amount. An amount cannot know what it
  # is being added to, so it stacked a second toe onto pictures that already had
  # one; the milky blacks in a graded photograph were this.
  def test_a_frame_whose_blacks_are_already_open_is_not_lifted_further
    Dir.mktmpdir do |dir|
      # Black point deliberately well above the toe target of 0.045.
      input = textured_field(dir, value: 150, sigma: 12)
      before = Postpro::Uncanny.black_point(Vips::Image.new_from_file(input))
      after = Postpro::Uncanny.black_point(Vips::Image.new_from_file(grade(input, "portrait", dir)))

      assert_operator before, :>, 0.045, "the fixture must start above the toe or it tests nothing"
      assert_operator after, :<, before + 0.02,
                      "blacks that arrived open at #{before.round(3)} came back at #{after.round(3)} — " \
                      "the toe is a floor to reach, not an amount to add"
    end
  end
end
