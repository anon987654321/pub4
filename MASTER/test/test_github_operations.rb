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

  def test_non_github_origin_is_not_pr_delivery
    exec = FakeExec.new([
      ["/tmp/pub4.git\n", FakeStatus.new(true)],
    ])
    operations = Master::Io::GitHubOperations.new(root: Dir.pwd, executor: exec)
    refute operations.github_remote?
  end
end
