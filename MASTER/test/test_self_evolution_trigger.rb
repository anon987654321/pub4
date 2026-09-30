# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class TestSelfEvolutionTrigger < Minitest::Test
  def test_skips_when_refactor_is_not_significant
    Dir.mktmpdir do |dir|
      git(dir, "init")
      FileUtils.mkdir_p(File.join(dir, "MASTER", "lib"))
      File.write(File.join(dir, "MASTER", "lib", "small.rb"), "A = 1\n")
      git(dir, "add", ".")
      git(dir, "commit", "-m", "base")
      File.write(File.join(dir, "MASTER", "lib", "small.rb"), "A = 2\n")

      result = Master::Trace::SelfEvolutionTrigger.new(root: dir).call

      assert_equal "self-evolution: no significant refactor", result
      refute File.exist?(File.join(dir, "runtime", "self_evolution.md"))
    end
  end

  def test_stays_dormant_when_self_evolution_is_disabled
    previous = ENV["MASTER_SELF_EVOLUTION"]
    ENV["MASTER_SELF_EVOLUTION"] = "0"
    dir = Dir.mktmpdir("self-evolution")

    result = Master::Trace::SelfEvolutionTrigger.new(root: dir).call

    assert_equal "self-evolution: disabled", result
  ensure
    ENV["MASTER_SELF_EVOLUTION"] = previous
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  private

  def git(dir, *args)
    _out, err, status = Open3.capture3("git", "-C", dir, *args)
    assert status.success?, err
  end
end
