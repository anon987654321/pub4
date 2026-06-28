# frozen_string_literal: true

require "fileutils"
require_relative "../test_helper"

class TestSocialSim < Minitest::Test
  def setup
    @runs = []
  end

  def teardown
    @runs.each { |path| FileUtils.rm_rf(path) }
  end

  def test_init_tick_and_metrics
    Master::Reach::SocialSim::Personas.stub(:sample, sample_personas) do
      result = Master::Reach::SocialSim::Inbox.init_run(
        subject_name: "ragnhild",
        persona_count: 2,
        seed: 42,
        root: Master::ROOT
      )
      run_dir = result[:run_dir]
      @runs << run_dir
      assert File.exist?(File.join(run_dir, "manifest.json"))
      assert File.exist?(File.join(run_dir, "state.json"))

      tick = Master::Reach::SocialSim::Director.tick(
        run_dir: run_dir,
        hours: 3,
        auto_mode: "not_interested"
      )
      assert tick[:metrics][:simulated_hour] >= 3
      assert File.exist?(File.join(run_dir, "metrics.json"))
      assert File.exist?(File.join(run_dir, "events.jsonl"))
    end
  end

  def test_guard_blocks_external_connector
    run_dir = File.join(Master::ROOT, "output", "social_sim", "guard_test_#{Process.pid}")
    FileUtils.mkdir_p(run_dir)
    @runs << run_dir
    assert_raises(Master::Reach::SocialSim::Guard::Violation) do
      Master::Reach::SocialSim::Guard.assert_sandbox!(run_dir: run_dir, options: { connector: "whatsapp" })
    end
  end

  def test_cli_parse_init
    parsed = Master::Reach::SocialSim::CLI.parse_args(%w[init --subject ragnhild --personas 8])
    assert_equal "init", parsed[:command]
    assert_equal "ragnhild", parsed[:options][:subject]
    assert_equal 8, parsed[:options][:personas]
  end

  def sample_personas
    [
      {
        id: "npc_a",
        handle: "@a_sim",
        archetype: "test",
        respect_boundaries: 0.5,
        patience_hours: 24,
        message_rate: 1.0,
        opener_pool: ["hello"],
        followup_pool: ["again"],
      },
      {
        id: "npc_b",
        handle: "@b_sim",
        archetype: "test",
        respect_boundaries: 0.5,
        patience_hours: 24,
        message_rate: 1.0,
        opener_pool: ["hi"],
        followup_pool: ["bump"],
      },
    ]
  end
end