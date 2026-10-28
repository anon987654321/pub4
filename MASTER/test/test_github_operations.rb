# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/io/github_operations"

class TestGitHubOperations < Minitest::Test
  FakeStatus = Struct.new(:success?)
  FakeExec = Struct.new(:responses) do
    def capture2e(*args, **_kwargs)
      response = responses.shift
      raise "unexpected command: #{args.join(" ")}" unless response
      response
    end
  end

  def test_normalize_github_ssh_remote
    exec = FakeExec.new([
      ["git@github.com:anon987654321/pub4.git\n", FakeStatus.new(true)],
      ["gh version 2\n", FakeStatus.new(true)],
      ["Logged in to github.com\n", FakeStatus.new(true)],
    ])
    operations = Master::Io::GitHubOperations.new(root: Dir.pwd, executor: exec)
    assert_predicate operations, :github_remote?
    assert_predicate operations, :available?
  end

  def test_merge_command_error_is_checked_against_authoritative_github_state
    head = "a" * 40
    merged = "b" * 40
    url = "https://github.com/anon987654321/pub4/pull/12"
    exec = FakeExec.new([
      ["gh version 2\n", FakeStatus.new(true)],
      ["Logged in to github.com\n", FakeStatus.new(true)],
      ["#{url}\n", FakeStatus.new(true)],
      ["OPEN\t#{head}\t\t\n", FakeStatus.new(true)],
      ["network connection reset\n", FakeStatus.new(false)],
      ["already merged\n", FakeStatus.new(false)],
      ["MERGED\t#{head}\t#{merged}\t2026-10-18T17:00:00Z\n", FakeStatus.new(true)],
    ])
    operations = Master::Io::GitHubOperations.new(
      root: Dir.pwd, repo: "anon987654321/pub4", executor: exec,
    )

    result = nil
    capture_io do
      result = operations.publish_and_merge!(
        branch: "master/fix-test", base: "main", expected_head: head,
        title: "test delivery", body: "body", timeout: 0
      )
    end

    assert result.ok, result.summary
    assert_equal 12, result.number
    assert_equal url, result.url
    assert_equal merged, result.merged_sha
    assert_match(/merged as #{merged[0, 12]}/, result.summary)
  end

  def test_merged_state_without_a_valid_sha_is_not_reported_as_success
    head = "a" * 40
    url = "https://github.com/anon987654321/pub4/pull/14"
    exec = FakeExec.new([
      ["gh version 2\n", FakeStatus.new(true)],
      ["Logged in to github.com\n", FakeStatus.new(true)],
      ["#{url}\n", FakeStatus.new(true)],
      ["OPEN\t#{head}\t\t\n", FakeStatus.new(true)],
      ["network connection reset\n", FakeStatus.new(false)],
      ["already merged\n", FakeStatus.new(false)],
      ["MERGED\t#{head}\tbad-sha\t2026-10-18T17:00:00Z\n", FakeStatus.new(true)],
    ])
    operations = Master::Io::GitHubOperations.new(
      root: Dir.pwd, repo: "anon987654321/pub4", executor: exec,
    )

    result = nil
    capture_io do
      result = operations.publish_and_merge!(
        branch: "master/fix-test", base: "main", expected_head: head,
        title: "test delivery", body: "body", timeout: 0
      )
    end

    refute result.ok
    assert_equal 14, result.number
    assert_equal url, result.url
    assert_nil result.merged_sha
    assert_match(/without a valid merge commit SHA/, result.summary)
  end

  def test_post_create_verification_failure_preserves_pr_recovery_details
    head = "a" * 40
    url = "https://github.com/anon987654321/pub4/pull/13"
    exec = FakeExec.new([
      ["gh version 2\n", FakeStatus.new(true)],
      ["Logged in to github.com\n", FakeStatus.new(true)],
      ["#{url}\n", FakeStatus.new(true)],
      ["API unavailable\n", FakeStatus.new(false)],
    ])
    operations = Master::Io::GitHubOperations.new(
      root: Dir.pwd, repo: "anon987654321/pub4", executor: exec,
    )

    result = nil
    capture_io do
      result = operations.publish_and_merge!(
        branch: "master/fix-test", base: "main", expected_head: head,
        title: "test delivery", body: "body", timeout: 0
      )
    end

    refute result.ok
    assert_equal 13, result.number
    assert_equal url, result.url
    assert_match(/delivery failed/i, result.summary)
  end

  def test_non_github_origin_is_not_pr_delivery
    exec = FakeExec.new([
      ["/tmp/pub4.git\n", FakeStatus.new(true)],
    ])
    operations = Master::Io::GitHubOperations.new(root: Dir.pwd, executor: exec)
    refute operations.github_remote?
  end
end
