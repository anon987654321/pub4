# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

# tools/example_scan.rb is the worked example AGENTS.md sends an agent to when
# it needs the scanner API. It claims it cannot go stale because it runs; this
# is what runs it, against a directory holding a file with a known finding.
class TestExampleScan < Minitest::Test
  TOOL = File.expand_path("../tools/example_scan.rb", __dir__)

  def test_the_worked_example_scans_a_directory_and_prints_its_findings
    Dir.mktmpdir("example_scan") do |dir|
      File.write(File.join(dir, "sample.rb"), "# frozen_string_literal: true\n\ndef sample\n  1   \nend\n")

      out, status = Open3.capture2e(RbConfig.ruby, TOOL, dir)

      assert status.success?, out
      assert_match(/\d+ rules registered/, out)
      assert_match(%r{sample\.rb:4: \[TRAILING_WHITESPACE\]}, out)
      count = out[/^(\d+) finding\(s\)$/, 1]
      refute_nil count, out
      assert_operator count.to_i, :>, 0
    end
  end
end
