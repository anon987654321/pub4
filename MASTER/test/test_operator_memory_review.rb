# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "fileutils"
require "stringio"
require "tmpdir"
require "operator/memory_review"

class TestOperatorMemoryReview < Minitest::Test
  def setup
    @root = Dir.mktmpdir("operator-memory-review")
    @master_root = File.join(@root, "MASTER")
    @evidence_dir = File.join(@master_root, "test", "fixtures")
    FileUtils.mkdir_p(@evidence_dir)
    @evidence_path = File.join(@evidence_dir, "review.txt")
    File.write(@evidence_path, "operator inspected the release artifact\n")
    @relative_evidence = "MASTER/test/fixtures/review.txt"
    @sha256 = Digest::SHA256.file(@evidence_path).hexdigest
    @memory = Master::Ground::Memory.new(root: @master_root)
    @memory.remember("deployment_target", "vm23", source: "operator:test", confidence: 0.9)
    @out = StringIO.new
    @err = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def invoke(*args)
    Operator::MemoryReview.run(
      args,
      root: @root,
      memory: @memory,
      out: @out,
      err: @err,
    )
  end

  def command(*extra)
    [
      "review", "deployment_target", "confirmed",
      "--evidence", @relative_evidence,
      "--sha256", @sha256,
      "--reviewer", "operator",
      *extra
    ]
  end

  def test_review_requires_explicit_confirmation
    status = invoke(*command)

    assert_equal 64, status
    assert_match(/--confirm is required/, @err.string)
    assert_nil @memory.provenance("deployment_target")["status"]
  end

  def test_verified_evidence_and_confirmation_record_auditable_review
    status = invoke(*command("--confirm"))

    assert_equal 0, status, @err.string
    assert_match(/memory0: reviewed deployment_target as confirmed/, @out.string)
    assert_includes @out.string, @sha256
    provenance = @memory.provenance("deployment_target")
    assert_equal "confirmed", provenance.fetch("status")
    assert_equal "operator", provenance.fetch("reviews").last.fetch("reviewer")
    assert_equal @sha256, provenance.fetch("reviews").last.fetch("sha256")
  end

  def test_digest_mismatch_fails_without_changing_memory
    status = invoke(
      "review", "deployment_target", "contradicted",
      "--evidence", @relative_evidence,
      "--sha256", "0" * 64,
      "--reviewer", "operator",
      "--confirm"
    )

    assert_equal 2, status
    assert_match(/SHA-256 mismatch/, @err.string)
    assert_nil @memory.provenance("deployment_target")["status"]
  end

  def test_paths_that_escape_the_repository_are_refused
    outside = File.join(File.dirname(@root), "outside-memory-evidence.txt")
    File.write(outside, "outside\n")
    status = invoke(
      "review", "deployment_target", "contradicted",
      "--evidence", "../outside-memory-evidence.txt",
      "--sha256", Digest::SHA256.file(outside).hexdigest,
      "--reviewer", "operator",
      "--confirm"
    )

    assert_equal 2, status
    assert_match(/path escapes its root/, @err.string)
    assert_nil @memory.provenance("deployment_target")["status"]
  ensure
    FileUtils.rm_f(outside) if outside
  end

  def test_symlink_to_outside_evidence_is_refused
    outside = File.join(File.dirname(@root), "outside-memory-symlink.txt")
    File.write(outside, "outside\n")
    link = File.join(@evidence_dir, "outside.txt")
    File.symlink(outside, link)
    status = invoke(
      "review", "deployment_target", "contradicted",
      "--evidence", "MASTER/test/fixtures/outside.txt",
      "--sha256", Digest::SHA256.file(outside).hexdigest,
      "--reviewer", "operator",
      "--confirm"
    )

    assert_equal 2, status
    assert_match(/symlink escapes its root/, @err.string)
    assert_nil @memory.provenance("deployment_target")["status"]
  ensure
    FileUtils.rm_f(link) if link
    FileUtils.rm_f(outside) if outside
  end

  def test_unknown_verdict_is_refused_without_mutation
    status = invoke(
      "review", "deployment_target", "guess",
      "--evidence", @relative_evidence,
      "--sha256", @sha256,
      "--reviewer", "operator",
      "--confirm"
    )

    assert_equal 2, status
    assert_match(/unknown memory review verdict/, @err.string)
    assert_nil @memory.provenance("deployment_target")["status"]
  end

  def test_operator_script_routes_the_memory_subcommand_to_this_handler
    script = File.read(File.expand_path("../bin/operator", __dir__))

    assert_includes script, 'require "operator/memory_review"'
    assert_includes script, 'when "memory"'
    assert_includes script, "Operator::MemoryReview.run(ARGV, root: ROOT)"
  end
end
