# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestEvolveFlow < Minitest::Test
  class StubChamber
    def deliberate(_code, filename:)
      MASTER::Result.err("stub failure on #{filename}")
    end
  end

  class StubLLM
    def configured?
      false
    end
  end

  def test_run_resets_history_between_invocations
    evolve = MASTER::Evolve.new(llm: StubLLM.new, chamber: StubChamber.new)

    first = evolve.run(path: MASTER.root, dry_run: true)
    second = evolve.run(path: MASTER.root, dry_run: true)

    assert_equal first[:files_processed], second[:files_processed]
    assert_equal first[:skipped], second[:skipped]
    assert_equal first[:errors], second[:errors]
    refute_empty second[:history]
  end

  def test_run_reports_skipped_when_llm_not_configured
    Dir.mktmpdir do |dir|
      lib_dir = File.join(dir, "lib")
      FileUtils.mkdir_p(lib_dir)
      file = File.join(lib_dir, "sample.rb")
      File.write(file, "puts 'hi'\n")

      evolve = MASTER::Evolve.new(llm: StubLLM.new, chamber: StubChamber.new)
      result = evolve.run(path: dir, dry_run: true)

      assert_equal 1, result[:files_processed]
      assert_equal 1, result[:skipped]
      assert_equal 0, result[:errors]
      assert_equal "OPENROUTER_API_KEY not configured", result[:history].first[:reason]
    end
  end
end
