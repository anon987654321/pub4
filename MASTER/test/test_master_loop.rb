# frozen_string_literal: true

require_relative "test_helper"

class TestMasterLoop < Minitest::Test
  LOOP_ENVS = %w[MASTER_AUTOFIX MASTER_WATCH MASTER_WATCHER MASTER_HEARTBEAT MASTER_BACKGROUND MASTER_LOOP].freeze

  def with_clean_env
    saved = LOOP_ENVS.to_h { |key| [key, ENV[key]] }
    LOOP_ENVS.each { |key| ENV.delete(key) }
    yield
  ensure
    LOOP_ENVS.each { |key| saved[key].nil? ? ENV.delete(key) : ENV[key] = saved[key] }
  end

  def test_master_loop_fix_enables_autofix_only
    with_clean_env do
      ENV["MASTER_LOOP"] = "fix"
      Master.apply_master_loop!
      assert_equal "1", ENV["MASTER_AUTOFIX"]
      assert_equal "0", ENV["MASTER_WATCH"]
      assert_equal "0", ENV["MASTER_WATCHER"]
    end
  end

  def test_data_file_resolves_renamed_limits
    assert File.exist?(Master.limits_path)
    assert Master.limits_path.end_with?("limits.yml")
    assert File.exist?(Master.state_path)
    assert Master.style_path.end_with?("style.yml")
  end

  def test_council_prompts_load_from_council_yml
    prompts = Master::Judge::Council::Deliberation.prompts
    assert prompts["judge"].to_s.include?("Council judge")
    assert prompts["juror"].to_s.include?("persona_name")
  end
end