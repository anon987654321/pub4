# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# The style stage of the /fix pass reads the marks operator-facing strings
# actually wear. The audit is scoped to the speaking trees, so a fixture tree
# holds the violations and the real tree stays out of the assertion.
class TestFixTypographyAudit < Minitest::Test
  Audit = Master::Fix::TypographyAudit

  def test_reports_the_marks_that_reached_a_person
    Dir.mktmpdir do |dir|
      write_cli_file(dir, 'lib/cli/fixture.rb', <<~RUBY)
        module Fixture
          LINE = "waiting for it..."
          DASH = "ready -- go"
          FLAGS = "--dry-run and --trace"
          GLOB = Dir.glob("lib/**/*.rb")
        end
      RUBY

      report = Audit.new(root: dir).call

      assert_match(/\Astyle0: 2 findings, 1 ascii ellipsis, 1 prose double dash\z/, report.lines.first)
      assert_match(/lib\/cli\/fixture\.rb:2 ascii ellipsis/, report)
      assert_match(/lib\/cli\/fixture\.rb:3 prose double dash/, report)
      refute_match(/FLAGS/, report, "flags keep their hyphens")
      refute_match(/GLOB/, report, "globs keep their dots")
    end
  end

  def test_a_clean_scope_reads_clean
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib", "voice"))
      File.write(File.join(dir, "lib", "voice", "clean.rb"), <<~RUBY)
        module Clean
          LINE = "waiting for it… — the note"
        end
      RUBY

      assert_match(/\Astyle0: clean/, Audit.new(root: dir).call)
    end
  end

  def test_a_scope_that_is_not_there_is_not_an_error
    Dir.mktmpdir do |dir|
      assert_match(/\Astyle0: clean/, Audit.new(root: dir).call)
    end
  end

  private

  def write_cli_file(root, relative, content)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
