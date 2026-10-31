# frozen_string_literal: true

require "minitest/autorun"

class PostproLegacyEffectsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  LEGACY = File.read(File.join(ROOT, "postpro", "legacy_effects.rb"))
  RECIPE = File.read(File.join(ROOT, "postpro", "lib", "recipe.rb"))
  DISPATCH = File.read(File.join(ROOT, "postpro", "lib", "grade_step.rb"))
  ENTRYPOINT = File.read(File.join(ROOT, "postpro", "postpro.rb"))

  RESTORED = %w[
    film_grain film_halation bloom_effect cross_process golden_hour_glow lomo
    sepia teal_and_orange anamorphic_simulation vhs_degrade color_fade soft_focus
    double_exposure polaroid_frame tape_degradation frame_distortion super8_flicker
    cinemascope_bars halftone_print film_scratches film_stock_emulation sprocket_holes
    lens_flare glitch
  ].freeze

  EXISTING_EQUIVALENTS = %w[
    light_leaks lens_distortion bleach_bypass day_for_night chromatic_aberration
  ].freeze

  def test_every_historical_effect_is_executable_or_has_a_current_equivalent
    missing_methods = RESTORED.reject { |name| LEGACY.match?(/\bdef\s+#{Regexp.escape(name)}\b/) }
    missing_recipe_names = RESTORED.reject do |name|
      RECIPE.match?(/\b#{Regexp.escape(name)}\b/)
    end

    assert_empty missing_methods, "missing restored implementations: #{missing_methods.join(', ')}"
    missing_dispatch_names = (RESTORED + EXISTING_EQUIVALENTS).reject { |name| DISPATCH.include?(name) }
    assert_empty missing_recipe_names, "missing recipe vocabulary: #{missing_recipe_names.join(', ')}"
    assert_empty missing_dispatch_names, "missing current dispatch equivalents: #{missing_dispatch_names.join(', ')}"
    assert_includes ENTRYPOINT, 'File.join(POSTPRO_DIR, "legacy_effects.rb")'
    assert_includes ENTRYPOINT, 'File.join(POSTPRO_DIR, "dilla_analog.rb")'
  end

  def test_historical_effect_inventory_has_no_duplicate_names
    assert_equal 24, RESTORED.uniq.length
    assert_equal 5, EXISTING_EQUIVALENTS.uniq.length
    assert_empty RESTORED & EXISTING_EQUIVALENTS
  end
end
