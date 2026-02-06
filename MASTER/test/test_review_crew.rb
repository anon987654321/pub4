# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

require_relative '../lib/master'
require_relative '../lib/cli'
require_relative '../lib/agents/review_crew'

class StubReviewLLM
  def chat(message, tier: nil)
    MASTER::Result.ok("ok")
  end
end

class ReviewTestCLI < MASTER::CLI
  private

  def setup_completion
  end

  def load_history
  end

  def setup_crash_recovery
  end

  def save_history
  end

  def save_state
  end
end

class TestReviewCrew < Minitest::Test
  def setup
    @llm = StubReviewLLM.new
  end

  def test_review_crew_runs_with_agents
    crew = MASTER::Agents::ReviewCrew.new(llm: @llm, principles: [])
    result = crew.review("def demo\n  puts 'hi'\nend\n", "demo.rb")
    assert result[:summary][:total_findings] >= 0
    assert result[:summary][:by_agent].key?("SecurityAgent")
  end

  def test_review_command_recurses_directories
    dir = Dir.mktmpdir('master_review_test')
    File.write(File.join(dir, 'one.rb'), "def one\n  1\nend\n")
    File.write(File.join(dir, 'two.rb'), "def two\n  2\nend\n")

    cli = ReviewTestCLI.new(llm: @llm, root: dir)
    output = cli.process_input("review #{dir}")

    assert_includes output, 'Review complete:'
    assert_includes output, 'across 2 files'
  ensure
    FileUtils.remove_entry(dir)
  end
end
