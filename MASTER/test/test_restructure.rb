# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

# The multi-file restructure /fix runs after its repair passes. Every case runs
# in a throwaway repository with its own bare remote, never this checkout.
class TestRestructure < Minitest::Test
  Restructure = Master::Fix::Restructure

  class Proof
    def initialize(failure = nil) = @failure = failure
    def baseline(_plan) = {}
    def failure(_plan, _before) = @failure
  end

  def setup
    @tmp = Dir.mktmpdir("restructure_test")
    remote = File.join(@tmp, "remote.git")
    @repo = File.join(@tmp, "work")
    sh("git", "init", "--bare", "--initial-branch=main", remote, chdir: @tmp)
    sh("git", "clone", remote, @repo, chdir: @tmp)
    %w[user.email=t@example.invalid user.name=T commit.gpgsign=false].each do |pair|
      sh("git", "config", *pair.split("=", 2), chdir: @repo)
    end
    write("MASTER/lib/big.rb", "class Big\n  def a = 1\n  def b = 2\nend\n")
    write("MASTER/lib/tiny.rb", "TINY = 1\n")
    sh("git", "add", "-A", chdir: @repo)
    sh("git", "commit", "-m", "first", chdir: @repo)
    sh("git", "push", "-u", "origin", "main", chdir: @repo)
  end

  def teardown = FileUtils.remove_entry(@tmp)

  def sh(*args, chdir:)
    out, status = Open3.capture2e(*args, chdir:)
    raise "#{args.join(" ")}: #{out}" unless status.success?

    out
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(@repo, path)))
    File.write(File.join(@repo, path), text)
  end

  def read(path) = File.read(File.join(@repo, path))

  def split_plan
    Restructure::Plan.parse(<<~TEXT)
      SUMMARY: split Big and absorb tiny.rb
      === WRITE MASTER/lib/big.rb
      class Big
        def a = 1
      end
      === WRITE MASTER/lib/big/second.rb
      class Big
        def b = 2
      end
      === DELETE MASTER/lib/tiny.rb
      === END
    TEXT
  end

  def restructure(proof = Proof.new) = Restructure.new(repo_root: @repo, proof:)

  def test_a_plan_reads_its_writes_deletes_and_summary
    plan = split_plan

    assert_equal "split Big and absorb tiny.rb", plan.summary
    assert_equal %w[MASTER/lib/big.rb MASTER/lib/big/second.rb], plan.writes.keys
    assert_equal ["MASTER/lib/tiny.rb"], plan.deletes
    assert_equal "class Big\n  def a = 1\nend\n", plan.writes["MASTER/lib/big.rb"]
  end

  def test_an_approved_restructure_is_committed_and_pushed
    result = restructure.call(split_plan, message: "refactor: split Big", review: ->(_diff) {})

    assert result.ok?, -> { result.message }
    refute File.exist?(File.join(@repo, "MASTER/lib/tiny.rb"))
    assert_equal "class Big\n  def b = 2\nend\n", read("MASTER/lib/big/second.rb")
    assert_equal "refactor: split Big", sh("git", "log", "-1", "--format=%s", "origin/main", chdir: @repo).strip
    assert_empty sh("git", "status", "--porcelain", chdir: @repo)
  end

  def test_a_rejected_restructure_puts_every_file_back
    seen = nil
    reject = lambda do |diff|
      seen = diff
      "REJECT: moves nothing useful"
    end
    result = restructure.call(split_plan, message: "x", review: reject)

    refute result.ok?
    assert_includes seen, "+++ MASTER/lib/big/second.rb"
    assert_includes seen, "+++ /dev/null"
    assert_equal "TINY = 1\n", read("MASTER/lib/tiny.rb")
    assert_equal "class Big\n  def a = 1\n  def b = 2\nend\n", read("MASTER/lib/big.rb")
    refute File.exist?(File.join(@repo, "MASTER/lib/big/second.rb"))
  end

  def test_a_failed_proof_puts_every_file_back
    result = restructure(Proof.new("MASTER no longer eager-loads")).call(split_plan, message: "x", review: ->(_d) {})

    assert_includes result.message, "eager-loads"
    assert_equal "TINY = 1\n", read("MASTER/lib/tiny.rb")
  end

  def test_the_kernel_and_other_trees_are_refused
    kernel = Restructure::Plan.parse("=== WRITE MASTER/data/soul.yml\nx\n=== END\n")
    outside = Restructure::Plan.parse("=== WRITE RAILS/app.rb\nx\n=== END\n")

    assert_includes restructure.call(kernel, message: "x", review: ->(_d) {}).message, "immutable"
    assert_includes restructure.call(outside, message: "x", review: ->(_d) {}).message, "outside MASTER/"
  end
end
