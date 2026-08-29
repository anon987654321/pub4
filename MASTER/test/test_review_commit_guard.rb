# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

# TODO.md, Test coverage: no test named CommitGuard. It is the anti-omission check
# — "did this commit quietly delete a public method?" — which is exactly the kind
# of guard that can stop working without anyone noticing, because a guard that
# finds nothing looks identical to a codebase with nothing wrong.
#
# Real git history in a temp repo, because from_git shells out to `git show`.
class CommitGuardTest < Minitest::Test
  def setup
    @repo = Dir.mktmpdir("commit_guard_test")
    sh("git", "init", "-q", "--initial-branch=main", ".")
    sh("git", "config", "user.email", "test@example.invalid")
    sh("git", "config", "user.name", "Test")
  end

  def teardown
    FileUtils.remove_entry(@repo)
  end

  def sh(*args)
    out, status = Open3.capture2e(*args, chdir: @repo)
    raise "#{args.join(" ")} failed: #{out}" unless status.success?

    out
  end

  def commit(relative, body, message)
    path = File.join(@repo, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    sh("git", "add", "-A")
    sh("git", "commit", "-qm", message)
  end

  THREE = <<~RUBY
    class Widget
      def alpha; end
      def beta; end
      def gamma; end
    end
  RUBY

  def two
    THREE.sub("  def beta; end\n", "")
  end

  def test_reports_a_method_that_was_removed
    commit("lib/widget.rb", THREE, "three methods")
    commit("lib/widget.rb", two, "drops beta")

    omissions = Master::Review::CommitGuard.new(root: @repo, depth: 1).check(paths: ["lib/widget.rb"])

    assert_equal ["Widget#beta"], omissions.map(&:name)
    assert_equal [:method], omissions.map(&:type)
    assert_equal ["lib/widget.rb"], omissions.map(&:path)
    assert_equal "HEAD~1", omissions.first.last_seen_at
  end

  def test_reports_a_removed_class
    commit("lib/pair.rb", "class A; end\nclass B; end\n", "two classes")
    commit("lib/pair.rb", "class A; end\n", "drops B")

    omissions = Master::Review::CommitGuard.new(root: @repo, depth: 1).check(paths: ["lib/pair.rb"])

    assert_includes omissions.map(&:name), "B"
  end

  def test_says_nothing_when_nothing_was_removed
    commit("lib/widget.rb", two, "two methods")
    commit("lib/widget.rb", THREE, "adds beta back")

    guard = Master::Review::CommitGuard.new(root: @repo, depth: 1)

    assert_empty guard.check(paths: ["lib/widget.rb"])
    assert_equal "commit_guard: no omissions detected", guard.render([])
  end

  # A rename is a removal from this guard's point of view, and should be, since
  # every caller of the old name is now broken.
  def test_a_rename_reads_as_an_omission
    commit("lib/widget.rb", "class Widget\n  def alpha; end\nend\n", "alpha")
    commit("lib/widget.rb", "class Widget\n  def renamed; end\nend\n", "renames alpha")

    omissions = Master::Review::CommitGuard.new(root: @repo, depth: 1).check(paths: ["lib/widget.rb"])

    assert_equal ["Widget#alpha"], omissions.map(&:name)
  end

  def test_non_ruby_and_missing_paths_are_skipped
    commit("README.md", "# hi\n", "readme")
    guard = Master::Review::CommitGuard.new(root: @repo, depth: 1)

    assert_empty guard.check(paths: ["README.md"])
    assert_empty guard.check(paths: ["lib/never_existed.rb"])
    assert_empty guard.check(paths: [])
  end

  def test_deeper_history_finds_an_older_removal
    commit("lib/widget.rb", THREE, "three")
    commit("lib/widget.rb", two, "drops beta")
    commit("lib/widget.rb", "#{two}# unrelated\n", "comment only")

    shallow = Master::Review::CommitGuard.new(root: @repo, depth: 1).check(paths: ["lib/widget.rb"])
    deep = Master::Review::CommitGuard.new(root: @repo, depth: 2).check(paths: ["lib/widget.rb"])

    assert_empty shallow, "the previous commit removed nothing"
    assert_includes deep.map(&:name), "Widget#beta"
  end

  def test_render_names_each_omission
    commit("lib/widget.rb", THREE, "three")
    commit("lib/widget.rb", two, "drops beta")
    guard = Master::Review::CommitGuard.new(root: @repo, depth: 1)
    text = guard.render(guard.check(paths: ["lib/widget.rb"]))

    assert_includes text, "1 omission(s)"
    assert_includes text, "Widget#beta"
    assert_includes text, "lib/widget.rb"
  end

  def test_default_depth_is_declared
    assert_equal 3, Master::Review::CommitGuard::DEFAULT_DEPTH
  end
end
