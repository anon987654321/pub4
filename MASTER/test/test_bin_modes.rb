# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# Every script under a bin/ directory that starts with a shebang is stored executable. bin/operator sat at
# 100644 in git, so fix-here could not run `operator triangle up`, the apps never booted, and every rendered
# check of a /fix RAILS run came back inconclusive with no RAILS app reachable.
class TestBinModes < Minitest::Test
  REPO = File.expand_path("..", Master::ROOT)

  def tracked_bins
    out, = Open3.capture2("git", "ls-files", "-s", chdir: REPO)
    rows = out.lines.map { |line| line.split(/\s+/, 4).map(&:strip) }
    rows.select { |_mode, _blob, _stage, path| path.match?(%r{(?:\A|/)bin/[^/]+\z}) }
  end

  def shebang?(path)
    File.open(File.join(REPO, path), "rb") { |file| file.read(2) == "#!" }
  rescue SystemCallError
    false
  end

  def test_every_shebang_script_under_bin_is_executable_in_git
    plain = tracked_bins.select { |mode, *, path| mode == "100644" && shebang?(path) }.map(&:last)

    assert_empty plain, "chmod +x and commit: #{plain.join(", ")}"
  end
end
