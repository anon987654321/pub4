# frozen_string_literal: true

require_relative "test_helper"

class TestSessionCapture < Minitest::Test
  def test_capture_writes_session_learning_and_yaml_registries
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "patterns.yml"), "---\n")
      File.write(File.join(dir, "data", "openbsd.yml"), "---\n")
      File.write(File.join(dir, "data", "soul.yml"), "---\n")

      result = Master::Trace::SessionCapture.new(root: dir).call(
        "successful refactor techniques=alias index recurring_patterns=stale TODO automations=batch audit prompts=show evidence providers=OpenBSD rcctl learned_behavior=verify before marking done"
      )

      assert_match(/capture: recorded/, result)
      assert_includes File.read(File.join(dir, "runtime", "session_learnings.md")), "What new techniques did the session uncover?"

      patterns = Master.load_yaml(File.join(dir, "data", "patterns.yml"))
      openbsd = Master.load_yaml(File.join(dir, "data", "openbsd.yml"))
      soul = Master.load_yaml(File.join(dir, "data", "soul.yml"))

      assert_includes patterns.dig("session_capture", "high_yield_prompts"), "show evidence"
      assert_includes openbsd["providers"], "OpenBSD rcctl"
      assert_includes soul["learned_behaviors"], "verify before marking done"
    end
  end

  def test_capture_command_is_registered
    commands = Master::Now::CommandRegistry.memory_commands(nil, nil, root: Dir.pwd)

    assert_includes commands.keys, "capture"
  end
end
