# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "test_helper"

class TestPhoenix < Minitest::Test
  def test_current_boundary_graph_is_clean
    report = Master::Phoenix.check

    assert report.clean, report.failures.join("\n")
    assert_equal %w[master rails openbsd studio], report.boundaries.map(&:name)
  end

  def test_boundary_lookup_under_master_root
    assert_equal "master", Master::Phoenix.boundary_for("lib/master.rb")
    assert_equal "rails", Master::Phoenix.boundary_for("../RAILS/brgen")
    assert_equal "studio", Master::Phoenix.boundary_for("tools/runs.rb")
  end

  def test_provenance_requires_the_five_architectural_facts
    dir = Dir.mktmpdir("phoenix")
    entry = Master::Phoenix.record_change(
      root: dir,
      boundary: "master",
      goal: "remove an unnecessary abstraction",
      constraints: ["preserve public commands"],
      alternatives: ["leave it", "replace it with a direct call"],
      evidence: { findings: 0, tests: ["test_phoenix"] },
      decision: "replace with the direct call"
    )

    assert_equal 1, entry[:schema]
    assert_equal "change", entry[:kind]
    assert_equal "master", entry[:boundary]
    assert File.file?(File.join(dir, Master::Phoenix::JOURNAL))
    assert_includes File.read(File.join(dir, Master::Phoenix::JOURNAL)), "unnecessary abstraction"
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  def test_production_evidence_is_append_only
    dir = Dir.mktmpdir("phoenix-evidence")
    Master::Phoenix.record_evidence(
      root: dir,
      boundary: "rails",
      signal: "request.p95_ms",
      value: 184,
      source: "production",
      context: { route: "/search" }
    )

    entry = JSON.parse(File.readlines(File.join(dir, Master::Phoenix::JOURNAL)).last)
    assert_equal "observation", entry["kind"]
    assert_equal "rails", entry["boundary"]
    assert_equal "request.p95_ms", entry["signal"]
    assert_equal 184, entry["value"]
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end
end
