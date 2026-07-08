# frozen_string_literal: true

require "test_helper"
require "now/core_bridge"
require "tmpdir"

# The bridge runs one goal through the kernel Fold from inside the CLI and streams
# turns to the event bus. These pin that it works fully offline (scripted model),
# returns a Fold summary, and publishes a turn event the dashboard can render.
class CoreBridgeTest < Minitest::Test
  class ScriptedModel
    def initialize(*effects) = @effects = effects
    def propose(_context, verbs:) = @effects.shift || Master::Core::Effect.done("done")
  end

  class FakeBus
    attr_reader :events
    def initialize = @events = []
    def publish(name, **payload) = @events << [name, payload]
  end

  # The real Constitution blocks `done` before an evidence threshold, so a
  # completing run must first produce passing exec evidence — same as production.
  def evidence_then_done(*extra, summary:)
    [
      *extra,
      Master::Core::Effect.exec(["true"], evidence: :test_pass),
      Master::Core::Effect.exec(["true"], evidence: :scan_clean),
      Master::Core::Effect.exec(["true"], evidence: :code_review),
      Master::Core::Effect.done(summary)
    ]
  end

  def test_run_returns_summary_and_streams_turns
    Dir.mktmpdir do |root|
      bus = FakeBus.new
      model = ScriptedModel.new(
        *evidence_then_done(Master::Core::Effect.write("note.txt", "hello\n"), summary: "wrote the note")
      )
      result = Master::Now::CoreBridge.run("write a note", root:, bus:, model:)

      assert_equal :complete, result[:reason]
      assert_equal "wrote the note", result[:summary]
      assert_equal "hello\n", File.read(File.join(root, "note.txt"))
      assert(bus.events.any? { |name, _| name == "core:turn" }, "expected a core:turn event")
    end
  end

  def test_run_string_renders_a_transcript
    Dir.mktmpdir do |root|
      model = ScriptedModel.new(*evidence_then_done(summary: "all clear"))
      out = Master::Now::CoreBridge.run_string("check", root:, model:)
      assert_match(/kernel: complete/, out)
      assert_match(/all clear/, out)
    end
  end

  def test_empty_goal_is_refused
    assert_equal "kernel: no goal", Master::Now::CoreBridge.run_string("   ", root: Dir.pwd)
  end
end
