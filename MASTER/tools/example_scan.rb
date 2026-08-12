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
#   3. Both return a Result. Ask ok?, then value! — there is no .findings.
#   4. depth: defaults shallow. The gates use :deep, and a shallow scan of a
#      clean-looking file is how "0 findings" gets reported having run half the
#      rules.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "master"

root = File.expand_path("..", __dir__)
scanner = Master::Review::Scan::InfraHelpers.build_scanner(root:)

puts "#{scanner.rules.size} rules registered, e.g. #{scanner.rules.first(5).map(&:id).join(', ')}"
puts

target = ARGV.first ? File.expand_path(ARGV.first, root) : File.join(root, "tools", "fixtures")

if File.directory?(target)
  # scan_dir returns Result[Hash[path => Result[Array[finding]]]] — a Result
  # wrapping a hash of Results, which is the shape that trips people up.
  result = scanner.scan_dir(target, depth: :deep, stream: false)
  abort "scan_dir failed: #{result.message}" unless result.ok?

  result.value!.each do |path, per_file|
    next unless per_file.respond_to?(:ok?) && per_file.ok?

    per_file.value!.each do |finding|
      puts "#{path.sub("#{root}/", '')}:#{finding[:line]}: [#{finding[:rule]}] #{finding[:message]}"
    end
  end
  files = result.value!.size
  found = result.value!.sum { |_, per_file| per_file.respond_to?(:ok?) && per_file.ok? ? per_file.value!.size : 0 }
  puts
  puts "#{files} file(s) scanned, #{found} finding(s)"
else
  # scan returns Result[Array[finding]]. A finding is a Hash with :rule,
  # :severity, :line and :message.
  result = scanner.scan(target, depth: :deep)
  abort "scan failed: #{result.message}" unless result.ok?

  result.value!.each do |finding|
    puts "#{ARGV.first}:#{finding[:line]}: [#{finding[:rule]}] #{finding[:severity]} — #{finding[:message]}"
  end
  puts
  puts "1 file scanned, #{result.value!.size} finding(s)"
end
