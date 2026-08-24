# frozen_string_literal: true

require "minitest/autorun"
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require_relative "../../app/services/shared/postpro_processor"

class PostproProcessorTest < Minitest::Test
  def test_script_resolves_to_studio_postpro
    with_env("PUB4_ROOT" => repo_root, "PUB4_RAILS_ROOT" => rails_root) do
      script = Shared::PostproProcessor.script
      assert script, "postpro script not found"
      assert_includes script.to_s, "/studio/postpro/postpro.rb"
      assert File.file?(script), "expected postpro at #{script}"
    end
  end

  def test_valid_presets_include_portrait_and_landscape
    assert_includes Shared::PostproProcessor::VALID_PRESETS, "portrait"
    assert_includes Shared::PostproProcessor::VALID_PRESETS, "landscape"
  end

  def test_skip_honors_env_flag
    with_env("SKIP_DEMO_POSTPRO" => "1") do
      assert Shared::PostproProcessor.skip?
    end
  end

  private

  def repo_root
    File.expand_path("../../../..", __dir__)
  end

  def rails_root
    File.join(repo_root, "RAILS")
  end

  def with_env(overrides)
    backup = overrides.keys.to_h { |key| [ key, ENV[key] ] }
    overrides.each { |key, value| ENV[key] = value }
    yield
  ensure
    backup.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
