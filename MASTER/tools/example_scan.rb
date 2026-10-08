# frozen_string_literal: true

# How to run MASTER's scanner from a script. Runnable, so it cannot go stale.
#
#   ruby MASTER/tools/example_scan.rb                    # scans the fixtures
#   ruby MASTER/tools/example_scan.rb lib/result.rb      # scans a path you name
#
# This exists because the API is guessable and every guess is wrong. On
# 2026-08-12 one session invented `Scanner.new(root:)`, `scan_file`, and
# `report.findings` in that order — none of which exist — and settled the
# question only by checking out a clean worktree. An LLM confabulating a
# plausible API is not a defect you can fix in the model; it is one you make
# cheap by leaving a worked example where it will be found.
#
# The four things worth knowing, all shown below:
#
#   1. Build the scanner with Master::Fix::Scanner.build(root:).
#   2. scan(path, depth:) takes a path; scan_dir(dir, depth:, stream:) takes a
#      directory. There is no scan_file.
#   3. findings(paths) is the flat API: an Array of finding Hashes with :path,
#      :line, :message. scan/scan_dir return Result-wrapped path/result pairs.
#   4. Use depth: :deep. Fix's scan contract is deep-only, so a partial walk
#      must never masquerade as a clean measurement.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "master"
require_relative "../lib/trace/dmesg"

root = File.expand_path("..", __dir__)
scanner = Master::Fix::Scanner.build(root:)

Master::Trace::Dmesg.attach("example0", "master0", "#{scanner.laws.size} laws registered")
Master::Trace::Dmesg.status("example0", "sample, #{scanner.laws.first(5).map(&:id).join(", ")}")

target = ARGV.first ? File.expand_path(ARGV.first, root) : File.join(root, "tools", "fixtures")
hits = scanner.findings([target], depth: :deep)
hits.each do |finding|
  rel = finding[:path].to_s.sub("#{root}/", "")
  Master::Trace::Dmesg.status("example0", "#{rel}:#{finding[:line]}, #{finding[:law]}, #{finding[:message]}")
end
Master::Trace::Dmesg.status("example0", "#{hits.size} finding(s)")
