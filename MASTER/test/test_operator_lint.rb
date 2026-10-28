# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "fix/scanner"
require "review/scan/law_dsl"
require "operator/lint"

# The pre-commit lint, `bin/operator lint --staged --changed-lines`, on a scratch
# repository with the real scanner and the real complexity law. A def-line
# finding is not judged by the def line alone, and a staged commit is not
# judged by the working tree's text.
module OperatorLintRepo
  BRANCHY = 12

  private

  def setup
    @dir = Dir.mktmpdir("operator-lint-")
    git("init", "-q")
    git("config", "user.email", "lint@example.invalid")
    git("config", "user.name", "lint")
    @path = File.join(@dir, "lib", "branchy.rb")
    FileUtils.mkdir_p(File.dirname(@path))
  end

  def teardown = FileUtils.rm_rf(@dir)

  def git(*args)
    out, status = Master::Io::Exec.capture2e("git", "-C", @dir, *args)
    assert status.success?, "git #{args.join(" ")}: #{out}"
    out
  end

  def scanner
    Master::Fix::Scanner.new(laws: [Master::Review::Scan::Laws::CyclomaticComplexityLaw.new])
  end

  # A method with +branches+ `if` lines, so complexity branches + 1.
  def branchy(branches, params: "value")
    body = Array.new(branches) { |i| "    return #{i} if value == #{i}\n" }.join
    "class Branchy\n  def decide(#{params})\n#{body}    nil\n  end\nend\n"
  end

  def commit(text)
    File.write(@path, text)
    git("add", "--", @path)
    git("commit", "-q", "-m", "base")
  end

  def stage(text)
    File.write(@path, text)
    git("add", "--", @path)
  end

  # The complexity findings a staged, changed-lines lint keeps; the scanner holds no other law.
  def complexity(lint = Operator::Lint.new(root: @dir, scanner:, staged: true, changed_only: true))
    lint.findings(lint.targets).map(&:last).select { |finding| finding[:law].to_s == "CYCLOMATIC_COMPLEXITY" }
  end
end

# A finding on a def line is the change's when the change touched the method and made it worse.
class TestOperatorLintMethodDebt < Minitest::Test
  include OperatorLintRepo

  def test_a_signature_only_touch_does_not_inherit_the_methods_standing_complexity
    commit(branchy(BRANCHY))
    stage(branchy(BRANCHY, params: "value, _unused = nil"))

    assert_empty complexity, "a def line touched alone does not report the method's old debt"
  end

  def test_a_change_deep_in_the_body_that_worsens_the_method_is_reported
    commit(branchy(BRANCHY))
    stage(branchy(BRANCHY + 1))

    found = complexity
    assert_equal 1, found.size, "a branch added inside the method made it worse"
    assert_match(/complexity #{BRANCHY + 2}\b/, found.first[:message])
    assert_equal 2, found.first[:line], "the finding still names the def line"
  end

  def test_a_body_change_that_leaves_the_measure_as_it_was_is_not_reported
    commit(branchy(BRANCHY))
    stage(branchy(BRANCHY).sub("return 3 if value == 3", "return 30 if value == 3"))

    assert_empty complexity
  end

  def test_a_method_new_over_the_limit_is_reported
    commit("class Branchy\nend\n")
    stage(branchy(BRANCHY))

    assert_equal 1, complexity.size
  end
end

# With --staged the commit's text is judged, whatever the working tree holds.
class TestOperatorLintStaged < Minitest::Test
  include OperatorLintRepo

  def test_staged_lints_the_staged_blob_not_the_working_tree
    commit(branchy(2))
    stage(branchy(3))
    # Another session's unstaged edit to the same file: complex, and lines shifted.
    File.write(@path, "# a\n# b\n# c\n#{branchy(BRANCHY + 5)}")

    assert_empty complexity, "the commit holds a three-branch method; the working tree is not committed"
  end

  def test_staged_reports_what_the_blob_holds_when_the_working_tree_is_clean
    commit(branchy(2))
    stage(branchy(BRANCHY))
    File.write(@path, branchy(2))

    assert_equal 1, complexity.size, "the staged blob is over the limit though the working tree is not"
  end

  def test_a_staged_file_gone_from_the_working_tree_is_still_judged
    commit("class Branchy\nend\n")
    stage(branchy(BRANCHY))
    File.delete(@path)

    lint = Operator::Lint.new(root: @dir, scanner:, staged: true, changed_only: true)
    assert_equal [@path], lint.targets
    assert_equal 1, complexity(lint).size
  end
end
