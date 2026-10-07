# frozen_string_literal: true

require "minitest/autorun"
require_relative "../dilla/lib/midi_effects"
require_relative "../dilla/lib/scene"

class TestDillaMidiEffects < Minitest::Test
  def events
    [
      DillaMidiEffects::Event.new(60, 0.0, 0.5, 0.4, :lead),
      DillaMidiEffects::Event.new(64, 0.5, 0.25, 0.3, :lead),
      DillaMidiEffects::Event.new(67, 0.75, 0.25, 0.35, :lead)
    ]
  end

  def test_chain_is_seed_reproducible
    a = DillaMidiEffects.apply(events, name: :alien, rng: Random.new(11))
    b = DillaMidiEffects.apply(events, name: :alien, rng: Random.new(11))
    assert_equal a.map(&:to_h), b.map(&:to_h)
  end

  def test_scale_effect_moves_out_of_scale
    out = DillaMidiEffects.scale(
      [DillaMidiEffects::Event.new(61, 0, 0.25, 0.3, :lead)],
      rng: Random.new(1),
      params: { scale_pcs: [0, 2, 4, 5, 7, 9, 11] }
    )
    assert_equal [60, 62, 64, 65, 67, 69, 71].include?(out.first.midi), true
  end

  def test_motif_events_keep_the_single_musical_object_shape
    result = DillaMidiEffects.motif_events(
      degrees: [0, 2, 1],
      root: 60,
      at: 0,
      beat: 0.5,
      rhythm: [1.0, 0.5, 0.5]
    )
    assert_equal [60, 62, 61], result.map(&:midi)
    assert_equal [0.0, 0.5, 1.0], result.map(&:at)
  end

  def test_scene_is_deterministic_and_contains_world_event
    scene = DillaScene.profile("flylo", index: 3, tension: 0.8)
    assert_equal "flylo", scene.fetch(:scene)
    assert_includes DillaScene::WORLD_EVENTS, scene.fetch(:world_event)
    assert scene.fetch(:fracture).between?(0.0, 1.0)
  end

  def test_journey_has_an_intentional_breakdown
    assert_equal :intro, DillaScene.journey(0, 10)
    assert_equal :breakdown, DillaScene.journey(6, 10)
    assert_equal :outro, DillaScene.journey(9, 10)
  end
end
