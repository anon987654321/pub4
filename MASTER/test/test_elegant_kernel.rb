# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "digest"
require "json"
require_relative "../lib/core/elegant_kernel"

class TestElegantKernel < Minitest::Test
  EK = Master::Core::ElegantKernel

  def with_workspace
    Dir.mktmpdir("pub4-elegant-kernel") do |root|
      File.write(File.join(root, ".pub4"), <<~YAML)
        schema: 1
        tree: test
        allows:
          master: read_write
          observer: read
        adapters: []
      YAML
      yield root
    end
  end

  def test_observation_is_a_hashed_snapshot
    with_workspace do |root|
      File.write(File.join(root, "sample.txt"), "before\n")
      kernel = EK::Kernel.new(root:, laws: [])
      observation = kernel.observe("sample.txt")
      assert_equal "snapshot sample.txt", observation.command
      assert_equal Digest::SHA256.hexdigest(observation.output), observation.hash
      assert_equal "before\n", observation.file("sample.txt")
      assert_nil observation.deleted, "deletion coverage is unknown outside a Git worktree"
      refute observation.deletions_known?
      assert_equal "observation", kernel.log.records.first.fetch("event")
    end
  end

  def test_fix_records_repair_and_verification_until_convergence
    with_workspace do |root|
      File.write(File.join(root, "sample.txt"), "bad value\n")
      builder = EK::Kernel.new(root:, laws: [])
      law = EK::Law.new(
        name: "replace_bad_value",
        auto: true,
        check: ->(observation) { observation.file("sample.txt").to_s.include?("bad") },
        repair: ->(observation) {
          builder.repair(observation, "sample.txt", observation.file("sample.txt").gsub("bad", "good"))
        }
      )
      kernel = EK::Kernel.new(root:, laws: [law])
      result = kernel.fix("sample.txt")
      assert result.converged?, result.message
      assert_equal "good value\n", File.read(File.join(root, "sample.txt"))
      events = kernel.log.records.map { |entry| entry.fetch("event") }
      assert_includes events, "observation"
      assert_includes events, "repair"
      assert_includes events, "apply"
      assert_includes events, "verify"
      assert_equal "converged", kernel.log.records.last.dig("data", "state")
    end
  end

  def test_sacred_law_escalates_without_mutating
    with_workspace do |root|
      File.write(File.join(root, "sample.txt"), "sacred\n")
      law = EK::Law.new(
        name: "preserve_sacred_file",
        sacred: true,
        auto: true,
        check: ->(observation) { observation.file("sample.txt").include?("sacred") },
        repair: ->(_observation) { flunk("sacred law must not repair") }
      )
      kernel = EK::Kernel.new(root:, laws: [law])
      result = kernel.fix("sample.txt")
      assert result.escalated?
      assert_equal "sacred\n", File.read(File.join(root, "sample.txt"))
      assert_equal "escalation", kernel.log.records.last.fetch("event")
    end
  end

  def test_boundary_denies_write_to_read_only_actor
    with_workspace do |root|
      File.write(File.join(root, "sample.txt"), "safe\n")
      boundary = EK::Boundary.new(root:, actor: "observer")
      assert_raises(EK::BoundaryError) { boundary.authorize!("sample.txt", access: :write) }
      assert_equal File.join(root, "sample.txt"), boundary.authorize!("sample.txt", access: :read)
    end
  end

  def test_existing_tree_manifests_preserve_read_only_master_boundaries
    repo_root = File.expand_path("../..", __dir__)
    boundary = EK::Boundary.new(root: repo_root, actor: "master")
    assert boundary.validate!
    assert_raises(EK::BoundaryError) { boundary.authorize!("RAILS/.pub4", access: :write) }
    assert_raises(EK::BoundaryError) { boundary.authorize!("OPENBSD/.pub4", access: :write) }
    assert_raises(EK::BoundaryError) { boundary.authorize!("STUDIO/.pub4", access: :write) }
    assert boundary.authorize!("RAILS/.pub4", access: :read)
  end

  def test_audit_chain_detects_tampering
    with_workspace do |root|
      log = EK::AuditLog.new(root:)
      log.append(event: "first", data: { value: 1 })
      log.append(event: "second", data: { value: 2 })
      assert_equal [1, 2], log.records.map { |entry| entry.fetch("seq") }
      assert_equal 1, log.replay(1).length
      lines = File.read(log.path).lines
      row = JSON.parse(lines[0])
      row["data"]["value"] = 99
      lines[0] = JSON.generate(row) + "\n"
      File.write(log.path, lines.join)
      assert_raises(EK::IntegrityError) { log.records }
    end
  end
end
