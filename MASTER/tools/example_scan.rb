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
#   1. Build the scanner with InfraHelpers.build_scanner(root:), not Scanner.new.
#   2. scan(path, depth:) takes a path; scan_dir(dir, depth:, stream:) takes a
#      directory. There is no scan_file.
#   3. findings(paths) is the flat API: an Array of Hashes with :path, :rule,
#      :line, :message. scan/scan_dir still return Result wrapping [path, Result]
#      pairs whose inner values are Hashes — f.rule raises, h[:rule] works.
#   4. depth: defaults shallow. The gates use :deep, and a shallow scan of a
#      clean-looking file is how "0 findings" gets reported having run half the
#      rules.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "master"
require_relative "../lib/trace/dmesg"

root = File.expand_path("..", __dir__)
scanner = Master::Fix::Scanner.build(root:)

Master::Trace::Dmesg.attach("example0", "master0", "#{scanner.rules.size} rules registered")
Master::Trace::Dmesg.status("example0", "sample, #{scanner.rules.first(5).map(&:id).join(", ")}")

target = ARGV.first ? File.expand_path(ARGV.first, root) : File.join(root, "tools", "fixtures")
hits = scanner.findings([target], depth: :deep)
hits.each do |finding|
  rel = finding[:path].to_s.sub("#{root}/", "")
  Master::Trace::Dmesg.status("example0", "#{rel}:#{finding[:line]}, #{finding[:rule]}, #{finding[:message]}")
end
Master::Trace::Dmesg.status("example0", "#{hits.size} finding(s)")
