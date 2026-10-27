# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "tools_helper"
ToolTest::Tools.load_tool("postpro/postpro.rb")
require_relative "postpro_fixtures"

# A take is refused when it stops being a grade of its source: shapes, black and
# white points and spread always; colour within its look's budget; skin tightest.
class TestPostproTakeCheck < Minitest::Test
  include PostproFixtures

  WIDTH = 240
  HEIGHT = 180

  # Thirds of a frame: skin, neutral grey, saturated colour, each over a
  # gradient with hard edges, so structure, neutrals and skin all read.
  def scene(brightness: 1.0)
    x = Vips::Image.xyz(WIDTH, HEIGHT).extract_band(0).cast(:float)
    y = Vips::Image.xyz(WIDTH, HEIGHT).extract_band(1).cast(:float)
    ramp = (y / HEIGHT) * 60 + ((x / 20).floor + (y / 20).floor).remainder(2) * 25
    third = (x / (WIDTH / 3)).floor
    red = (third == 0).ifthenelse(ramp + 160, (third == 1).ifthenelse(ramp + 90, ramp + 40))
    green = (third == 0).ifthenelse(ramp + 105, (third == 1).ifthenelse(ramp + 90, ramp + 130))
    blue = (third == 0).ifthenelse(ramp + 80, (third == 1).ifthenelse(ramp + 90, ramp + 30))
    (red.bandjoin([green, blue]) * brightness).cast(:uchar).copy(interpretation: :srgb)
  end

  def readings(take, source = scene) = send(:take_readings, source, take)
  def problems(take, source = scene, look: nil) = send(:take_problems, readings(take, source), send(:take_budget, look))
  def refused_for?(take, kind, **opts) = problems(take, **opts).any? { |problem| problem.start_with?(kind) }

  def test_the_fixture_has_skin_and_neutrals_to_judge
    source = readings(scene)
    refute_nil source[:skin], "the skin third must read as skin"
    refute_nil source[:neutral], "the grey third must read as neutral"
  end

  def test_the_source_itself_passes
    assert_empty problems(scene)
    assert_nil send(:check_take_survives!, scene, scene)
  end

  def test_a_gentle_film_grade_passes
    assert_empty problems(scene.linear([1.04, 1.0, 0.95], [3, 1, 0]).cast(:uchar))
  end

  def test_a_dark_photograph_is_judged_against_its_own_darkness
    dark = scene(brightness: 0.25)
    assert_operator send(:take_luma, dark).avg, :<, 40, "the fixture must be low-key"
    assert_empty problems(dark.linear(1.1, 2).cast(:uchar), dark)
  end

  def test_oversaturation_is_refused_by_default
    assert refused_for?(saturated(2.6), "colour")
  end

  def test_a_palette_look_may_spend_more_colour
    take = saturated(2.6)
    assert refused_for?(take, "colour")
    refute refused_for?(take, "colour", look: :neon_night)
  end

  def test_a_tint_on_the_neutrals_is_refused
    tinted = scene.cast(:float).linear([0.8, 1.0, 1.25], [-10, 0, 25]).cast(:uchar)
    assert refused_for?(tinted, "neutrals")
  end

  def test_turned_skin_is_refused
    turned = scene.extract_band(2).bandjoin([scene.extract_band(0), scene.extract_band(1)])
    assert refused_for?(turned, "skin")
  end

  def test_a_toned_monochrome_look_is_judged_on_shapes_and_tones_alone
    luma = scene.colourspace("b-w").extract_band(0).cast(:float)
    sepia = luma.bandjoin([luma * 0.9, luma * 0.72]).cast(:uchar)
    assert_empty problems(sepia)
  end

  def test_lost_shapes_are_refused
    assert refused_for?(scene.gaussblur(12).cast(:uchar), "structure")
  end

  def test_newly_blown_highlights_are_refused
    assert refused_for?(scene.linear(3.0, 40).cast(:uchar), "clipping")
  end

  def test_a_flattened_take_is_refused
    assert refused_for?((scene.cast(:float) * 0.2 + 100).cast(:uchar), "spread")
  end

  def test_a_look_budget_only_widens_its_baseline
    budget = send(:take_budget, :infrared_look)
    assert_equal TAKE_BUDGET.keys, budget.keys
    assert_equal LOOK_BUDGETS[:infrared_look][:skin], budget[:skin]
    assert_equal LOOK_BUDGET[:neutral], budget[:neutral], "a smaller own figure must not undercut the look baseline"
    assert_equal TAKE_BUDGET, send(:take_budget, nil)
    assert_equal LOOK_BUDGET, send(:take_budget, :a_look_with_no_budget)
  end

  def test_a_named_look_may_tint_more_than_a_light_take
    LOOK_BUDGET.each { |key, allowance| assert_operator allowance, :>=, TAKE_BUDGET[key] }
  end

  def test_every_look_budget_names_a_heavy_look
    assert_empty LOOK_BUDGETS.keys - HEAVY_LOOKS
  end

  def test_a_refusal_names_what_was_lost
    error = assert_raises(ArgumentError) { send(:check_take_survives!, scene.gaussblur(12).cast(:uchar), scene) }
    assert_match(/\Atake refused: .*structure/, error.message)
  end

  private

  def saturated(factor)
    grey = scene.colourspace("b-w").extract_band(0).cast(:float)
    ((scene.cast(:float) - grey) * factor + grey).cast(:uchar)
  end
end

# The effects rewritten to do what their processes do.
class TestPostproProcessEffects < Minitest::Test
  include PostproFixtures

  def frame = process_frame

  def luma(image) = image.colourspace("b-w").extract_band(0)
  def spread(image) = luma(image).percent(95) - luma(image).percent(5)

  def test_a_push_steepens_the_curve_rather_than_adding_exposure
    pushed = send(:push_pull, frame, 2.0, :tri_x)
    assert_operator spread(pushed), :>, spread(frame), "a push must raise contrast"
    assert_in_delta luma(frame).avg, luma(pushed).avg, 15, "a push must not brighten the frame wholesale"
    assert_operator (luma(pushed) >= 255).avg, :<, 1.0, "a pushed highlight blocks up, it does not clip"
  end

  def test_a_pull_softens_the_curve
    assert_operator spread(send(:push_pull, frame, -1.0, :tri_x)), :<, spread(frame)
  end

  def test_bleach_bypass_adds_density_and_contrast
    bleached = send(:bleach_bypass, frame, 0.6)
    assert_operator spread(bleached), :>, spread(frame)
    assert_operator luma(bleached).avg, :<=, luma(frame).avg + 1, "retained silver darkens, it never lightens"
  end

  def test_bleach_bypass_takes_colour_out
    chroma = ->(image) { image.colourspace(:lch).extract_band(1).avg }
    assert_operator chroma.call(send(:bleach_bypass, frame, 0.6)), :<, chroma.call(frame)
  end

  def test_teal_orange_cools_shadows_and_warms_highlights
    graded = send(:teal_orange, frame, 1.0)
    dark = frame.crop(0, 0, 30, 30)
    bright = frame.crop(170, 120, 30, 30)
    dark_out = graded.crop(0, 0, 30, 30)
    bright_out = graded.crop(170, 120, 30, 30)
    assert_operator dark_out.extract_band(2).avg - dark_out.extract_band(0).avg, :>,
                    dark.extract_band(2).avg - dark.extract_band(0).avg, "shadows move toward teal"
    assert_operator bright_out.extract_band(0).avg - bright_out.extract_band(2).avg, :>,
                    bright.extract_band(0).avg - bright.extract_band(2).avg, "highlights move toward warm"
  end

  def test_teal_orange_holds_skin
    skin = (Vips::Image.black(60, 60, bands: 3) + [205, 150, 120]).cast(:uchar).copy(interpretation: :srgb)
    moved = (send(:teal_orange, skin, 1.0).cast(:float) - skin.cast(:float)).abs.avg
    assert_operator moved, :<, 3.0, "skin moved #{moved.round(2)} levels"
  end

  def test_bloom_conserves_the_frames_light
    light = ->(image) { image.colourspace("scrgb").avg }
    assert_in_delta light.call(frame), light.call(send(:bloom_pro, frame, 1.0)), 0.01
  end

  def test_bloom_spreads_light_around_a_highlight
    lamp = (Vips::Image.black(120, 120, bands: 3) + 30).cast(:uchar).draw_circle([255, 255, 255], 60, 60, 6, fill: true)
                                                     .copy(interpretation: :srgb)
    near = ->(image) { image.crop(70, 55, 10, 10).avg }
    assert_operator near.call(send(:bloom_pro, lamp, 1.0)), :>, near.call(lamp)
  end

  def test_technicolor_adds_colour_without_a_global_saturation_slider
    chroma = ->(image) { image.colourspace(:lch).extract_band(1) }
    graded = send(:technicolor, frame, 0.6)
    assert_operator chroma.call(graded).avg, :>=, chroma.call(frame).avg * 0.95
    assert_operator chroma.call(graded).avg, :<, chroma.call(frame).avg * 1.6, "the old body lifted up to 1.7x"
  end

  def test_reciprocity_failure_is_a_cast_not_a_veil
    failed = send(:reciprocity_failure, grey_ramp, 30.0, :cinestill_800t)
    assert_equal 0, failed.crop(0, 0, 1, 8).max, "black must stay black: lost exposure cannot add light"
    linear = failed.colourspace("scrgb")
    assert_in_delta blue_over_green(linear, 60), blue_over_green(linear, 200), 0.02, "one cast ratio across tones"
  end

  def grey_ramp
    level = Vips::Image.xyz(256, 8).extract_band(0).cast(:uchar)
    level.bandjoin([level, level]).copy(interpretation: :srgb)
  end

  def blue_over_green(linear, column)
    patch = linear.crop(column, 0, 8, 8)
    patch.extract_band(2).avg / patch.extract_band(1).avg
  end

  def test_halation_runs_before_the_film_curve_in_every_preset
    late = PRESETS.select do |_, p|
      fx = p[:fx]
      fx.index("halation") && fx.index("film_curve") && fx.index("halation") > fx.index("film_curve")
    end
    assert_empty late.keys
  end
end

# A random take grades through the same calibrated dispatch a preset does.
class TestPostproOneDispatch < Minitest::Test
  include PostproFixtures

  def frame = process_frame

  def test_a_recipe_of_one_effect_matches_that_effect_in_a_preset
    head = send(:source_headroom, frame)
    preset_step = send(:grade_step, "bloom_pro", frame, { intensity: 0.9, stock: :kodak_portra }, head)
    recipe_step = send(:recipe_step, frame, "bloom_pro", { "intensity" => 0.9, "stock" => "kodak_portra" }, head)
    assert_equal 0.0, (preset_step.cast(:float) - recipe_step.cast(:float)).abs.max
  end

  def test_a_sharp_photograph_is_not_blurred_by_a_recipe
    noise = Vips::Image.gaussnoise(200, 150, mean: 128, sigma: 40)
    sharp = noise.bandjoin([noise, noise]).cast(:uchar).copy(interpretation: :srgb)
    assert_equal 0.0, send(:source_headroom, sharp)[:blur], "the fixture must read as already sharp"
    out = send(:recipe, sharp, [["optical_blur", 0.9]])
    assert_equal 0.0, (sharp.cast(:float) - out.cast(:float)).abs.max
  end

  def test_a_recipe_returns_eight_bit
    out = send(:recipe, frame, [["film_curve", { "intensity" => 0.8, "stock" => "kodak_portra" }], ["grain", 0.3]])
    assert_equal :uchar, out.format
    refute $postpro_float_pipeline, "the float pipeline must be switched off after a recipe"
  end

  def test_recipe_parameters_reach_the_step
    p = send(:recipe_preset, { "intensity" => 0.7, "stock" => "tri_x", "stops" => 2.0, "print_stock" => "kodak_2302" })
    assert_equal [0.7, :tri_x, 2.0, :kodak_2302], p.values_at(:intensity, :stock, :stops, :print_stock)
    assert_equal 0.4, send(:recipe_preset, 0.4)[:intensity]
    assert_equal 1.0, send(:recipe_preset, { "stock" => "tri_x" })[:intensity], "absent means default, not off"
  end

  def test_a_look_led_take_carries_the_preset_settings
    params = send(:preset_as_recipe, :noir).to_h
    assert_equal PRESETS[:noir][:stops], params.fetch("push_pull")["stops"]
    tokyo = send(:preset_as_recipe, :tokyo_night).to_h
    assert_equal PRESETS[:tokyo_night][:exposure_secs], tokyo.fetch("reciprocity_failure")["exposure_seconds"]
  end

  def test_an_unknown_recipe_effect_is_skipped_not_raised
    out = nil
    capture_io { out = send(:recipe_step, frame, "not_an_effect", 0.5, {}) }
    assert_equal frame, out
  end
end
