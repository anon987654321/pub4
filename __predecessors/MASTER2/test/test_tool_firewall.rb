# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "mode"

class ToolFirewallTest < Minitest::Test
  # ── ToolResult.normalize ──────────────────────────────────────────────

  def test_shell_ok_extracts_facts
    raw = "3 files, 0 errors"
    r   = MASTER::Executor::ToolResult.normalize("shell_command", raw)
    assert_equal "shell_command", r.tool
    assert r.facts.any?, "expected facts to be populated"
    assert_includes r.facts.join, "3 files"
  end

  def test_shell_blocked_sets_blocked_flag
    raw = "BLOCKED: dangerous shell command rejected"
    r   = MASTER::Executor::ToolResult.normalize("shell_command", raw)
    assert r.blocked?
    assert_includes r.to_prompt, "blocked:"
  end

  def test_file_write_captures_path
    raw = "Written 512 bytes to lib/foo.rb"
    r   = MASTER::Executor::ToolResult.normalize("file_write", raw)
    assert_includes r.files_touched, "lib/foo.rb"
    assert_includes r.facts.join, "512 bytes"
  end

  def test_file_read_reports_size
    raw = "x" * 200
    r   = MASTER::Executor::ToolResult.normalize("file_read", raw)
    assert_includes r.facts.join, "200 chars"
  end

  def test_web_normalizer_summarises
    raw = "Ruby is a dynamic language. It has closures. And blocks."
    r   = MASTER::Executor::ToolResult.normalize("web_search", raw)
    assert r.facts.any?
  end

  def test_content_hash_is_stable
    raw = "hello world"
    r1  = MASTER::Executor::ToolResult.normalize("shell_command", raw)
    r2  = MASTER::Executor::ToolResult.normalize("shell_command", raw)
    assert_equal r1.content_hash, r2.content_hash
    assert_equal 12, r1.content_hash.length
  end

  def test_to_prompt_contains_tool_and_hash
    r = MASTER::Executor::ToolResult.normalize("file_read", "some content")
    prompt = r.to_prompt
    assert_match(/tool=file_read/, prompt)
    assert_match(/hash=\w{12}/, prompt)
  end

  def test_to_prompt_never_exceeds_raw_passthrough_limit
    # raw output > 400 chars should be truncated in to_prompt
    raw    = "x" * 1000
    r      = MASTER::Executor::ToolResult.normalize("shell_command", raw)
    prompt = r.to_prompt
    # prompt must not contain the full raw (>400 chars of x's)
    refute prompt.include?("x" * 401), "to_prompt should not pass through >400 raw chars"
  end

  def test_error_output_flagged
    raw = "Error: something went wrong"
    r   = MASTER::Executor::ToolResult.normalize("shell_command", raw)
    assert r.error?
    assert_includes r.to_prompt, "error:"
  end

  # ── IntentClassifier ─────────────────────────────────────────────────

  def test_classifies_shell_transcript_as_ops
    input = "master@claude-4.5-sonnet*1c$ analyze lib/"
    assert_equal :ops, MASTER::IntentClassifier.detect(input)
  end

  def test_classifies_diff_as_refactor
    input = "diff --git a/foo.rb b/foo.rb\n--- a/foo.rb\n+++ b/foo.rb"
    assert_equal :refactor, MASTER::IntentClassifier.detect(input)
  end

  def test_classifies_plain_text_as_chat
    assert_equal :chat, MASTER::IntentClassifier.detect("hello, what is Ruby?")
  end

  def test_explicit_mode_overrides_detection
    assert_equal :ops, MASTER::IntentClassifier.detect("hello world", explicit: :ops)
  end

  def test_invalid_explicit_mode_falls_through_to_detect
    result = MASTER::IntentClassifier.detect("hello", explicit: :not_a_valid_mode)
    assert_equal :chat, result
  end

  # ── OutputGuard ───────────────────────────────────────────────────────

  def test_blocks_narrative_in_ops_mode
    candidate = "Chapter 5: The Watchers\nPart 2"
    result    = MASTER::OutputGuard.check(mode: :ops, candidate_text: candidate)
    assert result.err?
    assert_match(/narrative/, result.error)
  end

  def test_allows_narrative_in_chat_mode
    candidate = "Chapter 5: The Watchers"
    result    = MASTER::OutputGuard.check(mode: :chat, candidate_text: candidate)
    assert result.ok?
  end

  def test_allows_normal_ops_output
    candidate = "syntax ok\n3 files checked, 0 errors"
    result    = MASTER::OutputGuard.check(mode: :ops, candidate_text: candidate)
    assert result.ok?
  end

  def test_non_string_candidate_passes_through
    result = MASTER::OutputGuard.check(mode: :ops, candidate_text: nil)
    assert result.ok?
  end
end
