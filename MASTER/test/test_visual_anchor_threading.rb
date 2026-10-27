# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require File.expand_path("../lib/fix/visual_custody", __dir__)
require File.expand_path("../lib/fix/violation", __dir__)

# The selector a visual finding names is the fix's anchor: a chrome move inside
# it is the fix's own work, a chrome move elsewhere is drift. The anchor has to
# survive finding -> Violation -> RepairLoop#apply -> custody -> drift budget.
class TestVisualAnchorThreading < Minitest::Test
  Surface = Struct.new(:id, :viewport, :snapshot)
  Q = Master::Fix::VisualQualityChecks

  def test_violation_carries_the_finding_anchor
    v = Master::Fix::Violation.from_finding({ law: "X", line: 1, anchor: ".site-nav" }, file: "/a.scss")
    assert_equal ".site-nav", v[:anchor]
    assert_equal ".site-nav", v.to_h[:anchor]
  end

  def test_repair_loop_hands_the_anchor_to_custody
    Dir.mktmpdir do |root|
      path = File.join(root, "RAILS", "brgen", "app", "assets", "x.scss")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "a{}\n")
      seen = []
      custody = Object.new
      custody.define_singleton_method(:verify!) do |anchors: [], committer: nil|
        seen << anchors && Master::Result.ok(state: :preserved)
      end
      scanner = Object.new
      scanner.define_singleton_method(:scan) { |_p, laws: nil| Master::Result.ok([]) }
      loop = Master::Fix::RepairLoop.new(law: Struct.new(:id, :severity).new("TEST_RULE", :warning), agent: nil,
                                      scanner:, root:, visual_custody: custody)
      # This temporary Rails-shaped fixture has no app bin/rails or bundle. Stub
      # the focused-test runner and the compile check so this test isolates anchor
      # threading rather than an expected missing app in an artificial tree.
      loop.stub(:failing_test_for, nil) do
        Master::Fix::SourceCompile.stub(:failure, nil) do
          loop.send(:apply, path, "b{}\n", { law: "TEST_RULE", file: path, line: 1, anchor: ".site-nav" })
        end
      end
      assert_equal [[".site-nav"]], seen
    end
  end

  def test_custody_judge_exempts_the_anchored_chrome_move
    Dir.mktmpdir do |root|
      surface = Surface.new("brgen/home/mobile", "mobile", true)
      header = ->(y) { { "key" => "body>header.site>nav.top", "visible" => true, "text" => "", "rect" => { "x" => 0, "y" => y, "w" => 390, "h" => 56 } } }
      payload = ->(y) { { "vw" => 390, "vh" => 800, "scroll_width" => 390, "client_width" => 390, "elements" => [header.(y)] } }
      Q.record([{ surface:, payload: payload.(0).merge("composition" => { "state" => "resting" }) }], root:)
      ok = Master::Result.ok(state: :preserved)
      refute Q.judge([[surface, payload.(12)]], root:, prior: ok).ok?
      assert Q.judge([[surface, payload.(12)]], root:, prior: ok, anchors: ["nav.top"]).ok?
    end
  end
end
