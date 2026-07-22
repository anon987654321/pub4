# frozen_string_literal: true

require "json"
require "fileutils"
require "tmpdir"
require_relative "test_helper"
require_relative "../lib/cli/propose"

class TestProposeCorrections < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << { event:, payload: }
    end
  end

  class StubGit
    def dirty_count
      0
    end
  end

  class StubConfig
    def save!
      true
    end
  end

  def test_reject_appends_corrections_ledger_and_emits_user_correction
    root = Dir.mktmpdir("propose_corrections")
    bus = FakeBus.new
    propose = Master::CLI::Propose.new(
      container: {
        root:,
        bus:,
        git: StubGit.new,
        session: Struct.new(:messages).new([]),
        config: StubConfig.new,
      },
    )

    result = propose.reject("/fix")

    assert_equal "proposal rejected: /fix", result
    assert_includes bus.events.map { |e| e[:event] }, "user_correction"

    corrections = File.join(root, "runtime", "corrections.jsonl")
    assert File.exist?(corrections)
    row = JSON.parse(File.readlines(corrections).last)
    assert_equal "/fix", row["action"]
  ensure
    FileUtils.remove_entry(root) if root && Dir.exist?(root)
  end
end
