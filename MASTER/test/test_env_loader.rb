# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestEnvLoader < Minitest::Test
  def with_env_file(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.env")
      File.write(path, content)
      yield path
    end
  end

  def test_load_applies_key_value_pairs_from_file
    with_env_file("FOO_TEST_KEY=bar_value\n") do |path|
      Master::Ground::EnvLoader.load!(paths: [path])
      assert_equal "bar_value", ENV["FOO_TEST_KEY"]
    end
  ensure
    ENV.delete("FOO_TEST_KEY")
  end

  def test_load_strips_export_prefix
    with_env_file("export FOO_EXPORT_KEY=baz_value\n") do |path|
      Master::Ground::EnvLoader.load!(paths: [path])
      assert_equal "baz_value", ENV["FOO_EXPORT_KEY"]
    end
  ensure
    ENV.delete("FOO_EXPORT_KEY")
  end

  def test_load_skips_comments_and_blank_lines
    with_env_file("# a comment\n\nFOO_COMMENT_KEY=real_value\n") do |path|
      Master::Ground::EnvLoader.load!(paths: [path])
      assert_equal "real_value", ENV["FOO_COMMENT_KEY"]
    end
  ensure
    ENV.delete("FOO_COMMENT_KEY")
  end

  def test_load_never_overrides_an_already_set_env_var
    ENV["FOO_PRECEDENCE_KEY"] = "from_shell"
    with_env_file("FOO_PRECEDENCE_KEY=from_file\n") do |path|
      Master::Ground::EnvLoader.load!(paths: [path])
      assert_equal "from_shell", ENV["FOO_PRECEDENCE_KEY"]
    end
  ensure
    ENV.delete("FOO_PRECEDENCE_KEY")
  end

  def test_load_skips_unreadable_paths_without_raising
    loaded = Master::Ground::EnvLoader.load!(paths: ["/nonexistent/path/that/does/not/exist.env"])
    assert_empty loaded
  end

  # Regression: prepare_runtime! is the one call site every boot path goes
  # through before anything checks API keys (no_api_key_message tells users
  # to put their key in ~/.config/master/env and restart -- that instruction
  # only works if something actually reads the file, which nothing did until
  # this was wired in).
  def test_prepare_runtime_loads_env_file_before_anything_checks_keys
    with_env_file("MASTER_TEST_BOOT_KEY=loaded_at_boot\n") do |path|
      ENV["MASTER_ENV_FILE"] = path
      Master.prepare_runtime!
      assert_equal "loaded_at_boot", ENV["MASTER_TEST_BOOT_KEY"]
    end
  ensure
    ENV.delete("MASTER_TEST_BOOT_KEY")
    ENV.delete("MASTER_ENV_FILE")
  end
end
