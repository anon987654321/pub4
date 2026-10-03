#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs OPENBSD/test/test_*.rb, one process per file.
#
#   ruby OPENBSD/test/run_all.rb            # all of them
#   ruby OPENBSD/test/run_all.rb health     # only files matching /health/
#
# One process per file for the reasons RAILS/test/run_all.rb gives: files that
# share a process share every top-level constant, one `exit` anywhere ends the
# run early with Minitest reporting whatever it had, and a red result names no
# file. Exit status is the number of red files, capped at 255.

require "open3"
require "rbconfig"

root = File.expand_path("../..", __dir__)
filter = ARGV.first
# Written out from the repository root, so MASTER/tools/runs.rb reads the glob
# and counts every file it selects as run.
files = Dir.glob(File.join(root, "OPENBSD/test/**/test_*.rb")).sort
files = files.select { |path| path.include?(filter) } if filter
abort "openbsd contracts: no test files#{filter ? " matching #{filter.inspect}" : ''}" if files.empty?

red = files.reject do |path|
  out, status = Open3.capture2e({ "MT_NO_PLUGINS" => "1" }, RbConfig.ruby, path, chdir: root)
  tally = out[/^\d+ runs, \d+ assertions, \d+ failures, \d+ errors, \d+ skips/] || "no summary"
  puts format("openbsd contracts: %s %-40s %s", status.success? ? "ok  " : "FAIL", File.basename(path), tally)
  puts out.lines.grep(/^\s*\d+\) (Failure|Error):/).first(4).map { |line| "        #{line}" } unless status.success?
  status.success?
end

puts "openbsd contracts: #{files.size} file(s), #{red.size} red#{red.empty? ? '' : ": #{red.map { |p| File.basename(p) }.join(', ')}"}"
exit red.size.clamp(0, 255)
