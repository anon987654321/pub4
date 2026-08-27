# frozen_string_literal: true

require_relative "test_helper"

# Every require in an entry-point script must resolve to a file that exists.
#
# This gate exists because `MASTER/bin/pub4` was dead on main for six days and nothing
# reported it. `5203c698e` deleted `lib/pub4/status_report.rb` as an orphan while
# `MASTER/bin/pub4:12` required it, so every subcommand -- including the `MASTER/bin/pub4
# status` CLAUDE.md documents as the repo-level check -- died with a LoadError
# before it parsed argv.
#
# The orphan sweep that deleted it was not careless; it was blind twice over, and
# both blindnesses are reproducible:
#
#   1. Extension filter. The sweep matched each file's innermost constant with a
#      grep over *.rb, *.yml and *.md. `MASTER/bin/pub4` has no extension, so its
#      `Pub4::StatusReport` call was invisible. Re-running that grep today still
#      returns zero callers for a constant that plainly has one.
#   2. Scope. The sweep ran from MASTER/, where `bin/` means `MASTER/bin/`. The
#      caller lives in the *repo root* `bin/`, one directory above the scan root,
#      and puts MASTER/lib on the load path itself (`MASTER/bin/pub4:9`).
#
# So this checks the requires rather than the constants: it does not care how a
# file is referenced, only that what a runnable script asks for is on disk. A
# constant sweep can be fooled by an extension filter. A missing file cannot.
class TestEntrypointRequires < Minitest::Test
  MASTER_ROOT = File.expand_path("..", __dir__)
  REPO_ROOT = File.expand_path("..", MASTER_ROOT)
  LIB = File.join(MASTER_ROOT, "lib")

  # Top-level directories under MASTER/lib. A `require "x/y"` whose first segment
  # is one of these is ours and must resolve; anything else is stdlib or a gem
  # and is not this test's business.
  def internal_namespaces
    @internal_namespaces ||= Dir.children(LIB).select { |e| File.directory?(File.join(LIB, e)) }.to_set
  end

  def entrypoints
    (Dir.glob(File.join(REPO_ROOT, "bin", "*")) + Dir.glob(File.join(MASTER_ROOT, "bin", "*")))
      .select { |path| File.file?(path) && File.executable?(path) }
      .reject { |path| File.extname(path) == ".md" }
      .sort
  end

  def test_every_entrypoint_is_executable_and_present
    refute_empty entrypoints, "no executable entry points found -- the glob is wrong, not the tree"
  end

  def test_internal_requires_resolve
    missing = []

    entrypoints.each do |script|
      source = File.read(script)
      next unless source.start_with?("#!") && source.match?(/\bruby\b/)

      source.scan(/^\s*require\s+["']([^"']+)["']/) do |(feature)|
        next unless internal_namespaces.include?(feature.split("/").first)
        next if File.file?(File.join(LIB, "#{feature}.rb"))

        missing << "#{script.delete_prefix("#{REPO_ROOT}/")} requires #{feature.inspect}, " \
                   "but lib/#{feature}.rb does not exist"
      end
    end

    assert_empty missing, <<~MESSAGE
      An entry-point script requires a file that is not on disk. It will die with
      a LoadError before it runs. Restore the file or fix the require.

      #{missing.join("\n")}
    MESSAGE
  end

  # The specific regression, named, so a future orphan sweep that deletes it
  # again fails with the reason rather than a generic missing-file line.
  def test_bin_pub4_status_report_is_present
    assert_path_exists File.join(LIB, "pub4", "status_report.rb"),
                       "MASTER/bin/pub4 requires pub4/status_report and calls Pub4::StatusReport at :48. " \
                       "It is not an orphan. A constant grep filtered by file extension cannot see " \
                       "the caller, because MASTER/bin/pub4 has no extension."
  end
end
