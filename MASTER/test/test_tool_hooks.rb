# frozen_string_literal: true

require "test_helper"
require "cli/tool_hooks"
require "tmpdir"

# Configured PreToolUse hooks add refusals. Faults fail closed by default;
# an explicit on_fault: allow is the only route to fail-open behavior.
class ToolHooksTest < Minitest::Test
  def hook_file(dir, script, matcher: nil, on_fault: nil)
    guard = File.join(dir, "guard.rb")
    File.write(guard, script)
    file = File.join(dir, "hooks.yml")
    row = { "command" => [RbConfig.ruby, guard] }
    row["matcher"] = matcher if matcher
    row["on_fault"] = on_fault if on_fault
    File.write(file, YAML.dump("PreToolUse" => [row]))
    file
  end

  DENY_RM = <<~RUBY
    require "json"
    input = JSON.parse($stdin.read)
    if input.dig("tool_input", "command").to_s.include?("deploy")
      warn "deploy needs a person"
      exit 2
    end
  RUBY

  def test_exit_two_refuses_with_stderr_as_the_reason
    Dir.mktmpdir do |dir|
      hooks = Master::CLI::ToolHooks.entries(hook_file(dir, DENY_RM))
      reason = Master::CLI::ToolHooks.refusal("Bash", { command: "vps-deploy" }, root: dir, hooks:)
      assert_includes reason, "deploy needs a person"
      assert_nil Master::CLI::ToolHooks.refusal("Bash", { command: "ls" }, root: dir, hooks:)
    end
  end

  def test_matcher_limits_the_hook_to_its_tools
    Dir.mktmpdir do |dir|
      hooks = Master::CLI::ToolHooks.entries(hook_file(dir, "exit 2", matcher: "Bash"))
      assert Master::CLI::ToolHooks.refusal("Bash", { command: "ls" }, root: dir, hooks:)
      assert_nil Master::CLI::ToolHooks.refusal("Write", { file_path: "a" }, root: dir, hooks:)
    end
  end

  def test_a_faulting_hook_denies_by_default
    Dir.mktmpdir do |dir|
      hooks = Master::CLI::ToolHooks.entries(hook_file(dir, "exit 1"))
      reason = nil
      _, err = capture_io do
        reason = Master::CLI::ToolHooks.refusal("Bash", { command: "ls" }, root: dir, hooks:)
      end
      assert_includes err, "refusing"
      assert_includes reason, "on_fault: deny"
    end
  end

  def test_explicit_on_fault_allow_is_the_only_fail_open_mode
    Dir.mktmpdir do |dir|
      hooks = Master::CLI::ToolHooks.entries(hook_file(dir, "exit 1", on_fault: "allow"))
      _, err = capture_io do
        assert_nil Master::CLI::ToolHooks.refusal("Bash", { command: "ls" }, root: dir, hooks:)
      end
      assert_includes err, "allowing by explicit on_fault: allow"
    end
  end

  def test_wrapped_sandbox_keeps_the_base_answer_when_no_hook_refuses
    Dir.mktmpdir do |dir|
      hooks = Master::CLI::ToolHooks.entries(hook_file(dir, DENY_RM))
      sandbox = Master::CLI::ToolHooks.wrap_sandbox(->(argv) { argv.first == "rm" ? "no rm" : nil }, root: dir, hooks:)
      assert_equal "no rm", sandbox.call(%w[rm x])
      assert_nil sandbox.call(%w[ls])
      assert_includes sandbox.call(%w[vps-deploy]), "deploy needs a person"
    end
  end

  def test_no_hooks_file_returns_the_base_unchanged
    base = ->(_argv) { nil }
    assert_same base, Master::CLI::ToolHooks.wrap_sandbox(base, root: "/", hooks: [])
    assert_empty Master::CLI::ToolHooks.entries(File.join(Dir.tmpdir, "no-such-hooks.yml"))
  end

  def test_wrapped_verifier_adds_the_refusal_to_the_findings
    Dir.mktmpdir do |dir|
      hooks = Master::CLI::ToolHooks.entries(hook_file(dir, "exit 2"))
      verifier = Master::CLI::ToolHooks.wrap_verifier(->(path:, content:) { ["LAW:1 #{path}#{content}"] }, root: dir, hooks:)
      findings = verifier.call(path: "a.rb", content: "x")
      assert_equal 2, findings.size
      assert_includes findings.first, "LAW:1"
    end
  end

  def test_on_fault_deny_refuses_when_the_hook_crashes
    Dir.mktmpdir do |dir|
      hooks = Master::CLI::ToolHooks.entries(hook_file(dir, "exit 1", on_fault: "deny"))
      reason = nil
      capture_io { reason = Master::CLI::ToolHooks.refusal("Bash", { command: "ls" }, root: dir, hooks:) }
      assert_includes reason, "on_fault: deny"
    end
  end

  def test_on_fault_deny_refuses_when_the_program_is_missing
    hooks = [[nil, ["/no/such/hook-program"], true]]
    reason = nil
    capture_io { reason = Master::CLI::ToolHooks.refusal("Bash", { command: "ls" }, root: Dir.tmpdir, hooks:) }
    assert_includes reason, "on_fault: deny"
  end

  def test_a_hooks_file_others_can_write_fails_closed
    Dir.mktmpdir do |dir|
      file = hook_file(dir, "exit 2")
      File.chmod(0o666, file)
      hooks = nil
      _, err = capture_io { hooks = Master::CLI::ToolHooks.entries(file) }
      assert_includes err, "effects will be refused"
      reason = Master::CLI::ToolHooks.refusal("Bash", { command: "ls" }, root: dir, hooks:)
      assert_includes reason, "untrusted"
    end
  end

  def test_a_malformed_hooks_file_fails_closed
    Dir.mktmpdir do |dir|
      file = File.join(dir, "hooks.yml")
      File.write(file, "PreToolUse: [")
      File.chmod(0o600, file)
      hooks = nil
      _, err = capture_io { hooks = Master::CLI::ToolHooks.entries(file) }
      assert_includes err, "effects will be refused"
      reason = Master::CLI::ToolHooks.refusal("Bash", { command: "ls" }, root: dir, hooks:)
      assert_includes reason, "untrusted"
    end
  end
end
