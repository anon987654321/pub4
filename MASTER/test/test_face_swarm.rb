# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/face/swarm"

class TestFaceSwarm < Minitest::Test
  Swarm = Master::Face::Swarm
  Particle = Swarm::Particle

  def deep_config
    Marshal.load(Marshal.dump(Swarm.config))
  end

  def still_particle(x:, y: 0.0, z: 0.0, depth_rank: nil)
    Particle.new(
      x:, y:, z:, vx: 0.0, vy: 0.0, vz: 0.0,
      depth_rank: depth_rank || Swarm.depth_rank(z), home_depth: z
    )
  end

  def test_tokens_define_the_enabled_design_and_all_target_regions
    settings = Swarm.config

    assert_equal true, settings.fetch("enabled")
    assert_equal 240, settings.fetch("particle_budget")
    assert_equal ["·", "˙", "∘", "•", "○", "●"], settings.fetch("glyph_ramp")
    assert_equal [1.18, 1.02, 0.82], settings.dig("target_field", "head", "scale")
    assert_equal [-0.29, 0.21, 0.58], settings.dig("target_field", "eyes", "left", "pos")
    assert_equal [0.29, 0.21, 0.58], settings.dig("target_field", "eyes", "right", "pos")
    assert_equal [0.0, -0.31, 0.50], settings.dig("target_field", "mouth", "pos")
    assert_equal 0.72, settings.dig("target_field", "softness")
  end

  def test_mode_names_resolve_to_the_three_token_driven_force_profiles
    assert_equal "idle", Swarm.canonical_mode(:sleeping)
    assert_equal "attentive", Swarm.canonical_mode(:listening)
    assert_equal "attentive", Swarm.canonical_mode(:working)
    assert_equal "thinking", Swarm.canonical_mode(:thinking)
    assert_equal 1.35, Swarm.mode_multipliers(:listening).fetch("eyes")
    assert_equal 0.22, Swarm.mode_multipliers(:thinking).fetch("noise")
  end

  def test_particle_budget_is_capped_by_existing_spatial_contract
    assert_equal 240, Swarm.particle_budget
    assert_equal 240, Swarm.particle_budget(mobile: true)
    assert_equal 240, Swarm.particle_budget(reduced_motion: true)
    assert_equal 240, Swarm.particle_budget(mobile: true, reduced_motion: true)
    assert_equal 240, Swarm.build(count: 10_000, seed: 7).length
    assert_equal 240, Swarm.build(count: 10_000, seed: 7, mobile: true).length
    assert_equal 0, Swarm.build(count: -3, seed: 7).length
  end

  def test_initial_cloud_is_seeded_and_every_particle_has_finite_state
    first = Swarm.build(count: 80, seed: 1234)
    second = Swarm.build(count: 80, seed: 1234)

    assert_equal first.map(&:to_h), second.map(&:to_h)
    assert_equal 80, first.length
    first.each do |particle|
      %i[x y z vx vy vz depth_rank home_depth].each do |key|
        assert particle.public_send(key).is_a?(Numeric)
        assert particle.public_send(key).finite?
      end
      assert_includes 0.0..1.0, particle.depth_rank
      assert_includes -1.1..1.1, particle.z
    end
  end

  def test_depth_mapping_and_glyph_ramp_share_the_same_endpoints
    settings = Swarm.config
    ramp = settings.fetch("glyph_ramp")

    assert_equal 0.0, Swarm.depth_rank(-2.0)
    assert_equal 0.5, Swarm.depth_rank(0.0)
    assert_equal 1.0, Swarm.depth_rank(2.0)
    assert_equal ramp.first, Swarm.glyph_for(0.0, config: settings)
    assert_equal ramp.last, Swarm.glyph_for(1.0, config: settings)
    assert_equal ramp[3], Swarm.glyph_for(0.6, config: settings)
  end

  def test_head_attractor_pulls_particles_back_toward_the_field
    settings = deep_config
    settings["noise_scale"] = 0.0
    settings["cohesion_radius"] = 0.0
    settings["separation_radius"] = 0.0
    settings["target_field"]["head"] = {
      "center" => [0.0, 0.0, 0.0], "scale" => [1.0, 1.0, 1.0], "weight" => 1.0
    }
    settings["target_field"]["eyes"].each_value { |eye| eye["weight"] = 0.0 }
    settings["target_field"]["mouth"]["weight"] = 0.0
    particle = still_particle(x: 0.8)

    Swarm.update!([particle], mode: :idle, dt: 0.05, config: settings, rng: Random.new(1))

    assert_operator particle.x, :<, 0.8
    assert_operator particle.vx, :<, 0.0
  end

  def test_separation_pushes_close_particles_apart
    settings = deep_config
    settings["noise_scale"] = 0.0
    settings["cohesion_radius"] = 0.0
    settings["separation_radius"] = 0.2
    settings["separation_strength"] = 0.5
    settings["target_field"]["head"]["weight"] = 0.0
    settings["target_field"]["eyes"].each_value { |eye| eye["weight"] = 0.0 }
    settings["target_field"]["mouth"]["weight"] = 0.0
    particles = [still_particle(x: -0.05), still_particle(x: 0.05)]
    before = particles.last.x - particles.first.x

    Swarm.update!(particles, mode: :idle, dt: 0.05, config: settings, rng: Random.new(1))

    assert_operator particles.last.x - particles.first.x, :>, before
  end

  def test_cohesion_pulls_neighbors_toward_each_other
    settings = deep_config
    settings["noise_scale"] = 0.0
    settings["cohesion_radius"] = 0.2
    settings["cohesion_strength"] = 1.0
    settings["separation_radius"] = 0.0
    settings["target_field"]["head"]["weight"] = 0.0
    settings["target_field"]["eyes"].each_value { |eye| eye["weight"] = 0.0 }
    settings["target_field"]["mouth"]["weight"] = 0.0
    particles = [still_particle(x: -0.05), still_particle(x: 0.05)]
    before = particles.last.x - particles.first.x

    Swarm.update!(particles, mode: :idle, dt: 0.05, config: settings, rng: Random.new(1))

    assert_operator particles.last.x - particles.first.x, :<, before
  end

  def test_force_step_is_deterministic_with_a_supplied_random_generator
    left = Swarm.build(count: 20, seed: 23)
    right = Swarm.build(count: 20, seed: 23)

    3.times do
      Swarm.update!(left, mode: :thinking, dt: 0.016, rng: Random.new(99))
      Swarm.update!(right, mode: :thinking, dt: 0.016, rng: Random.new(99))
    end

    assert_equal left.map(&:to_h), right.map(&:to_h)
  end

  def test_integration_clamps_dt_and_keeps_positions_inside_the_bounded_field
    settings = deep_config
    particles = Swarm.build(count: 50, seed: 40)

    Swarm.update!(particles, mode: :thinking, dt: 20.0, config: settings, rng: Random.new(1))

    head = settings.dig("target_field", "head")
    center = head.fetch("center")
    scale = head.fetch("scale")
    particles.each do |particle|
      assert_operator particle.x, :>=, center[0] - scale[0] * 1.25
      assert_operator particle.x, :<=, center[0] + scale[0] * 1.25
      assert_operator particle.y, :>=, center[1] - scale[1] * 1.25
      assert_operator particle.y, :<=, center[1] + scale[1] * 1.25
      assert_operator particle.z, :>=, center[2] - scale[2] * 1.25
      assert_operator particle.z, :<=, center[2] + scale[2] * 1.25
      assert_includes 0.0..1.0, particle.depth_rank
    end
  end

  def test_reduced_motion_freezes_positions_and_velocities
    simulation = Swarm::Simulation.new(seed: 77, count: 32)
    simulation.step(mode: :idle, time: 0.0)
    before = simulation.particles.map(&:to_h)

    simulation.step(mode: :thinking, time: 1.0, reduced_motion: true)

    assert_equal before, simulation.particles.map(&:to_h)
  end

  def test_current_cli_face_renderer_uses_the_swarm_and_can_disable_it
    original = ENV["MASTER_FACE_SWARM"]
    original_budget = ENV["MASTER_FACE_SWARM_BUDGET"]
    ENV["MASTER_FACE_SWARM"] = "1"
    ENV["MASTER_FACE_SWARM_BUDGET"] = "20"
    face = Master::CLI::Face
    options = { state: :idle, rows: 12, cols: 24, t: 0.0, motion: Master::CLI::Face::Motion.new, show_laws: false }
    particle_frame = face.frame(**options)

    assert_match(/[·˙∘•○●]/, particle_frame)
    swarm_key = [12, 24, 20]
    assert_equal 20, face::SWARMS.fetch(swarm_key).particles.length

    ENV["MASTER_FACE_SWARM"] = "0"
    plain_frame = face.frame(**options)
    refute_match(/[·˙∘•○●]/, plain_frame)
  ensure
    ENV["MASTER_FACE_SWARM"] = original
    ENV["MASTER_FACE_SWARM_BUDGET"] = original_budget
  end

  def test_cli_projection_is_bounded_and_near_particles_win_collisions
    frame_class = Struct.new(:chars, :depth)
    frame = frame_class.new(Array.new(15) { Array.new(31, " ") }, Array.new(15) { Array.new(31, 1) })
    far = still_particle(x: 0.0, y: 0.05, z: -0.7, depth_rank: 0.1)
    near = still_particle(x: 0.0, y: 0.05, z: 0.8, depth_rank: 0.9)

    Swarm.overlay!(frame, [near, far])

    assert_equal "●", frame.chars[7][15]
    assert_equal 2, frame.depth[7][15]
    assert_equal 15, frame.chars.length
    assert frame.chars.all? { |row| row.length == 31 }
  end
end
