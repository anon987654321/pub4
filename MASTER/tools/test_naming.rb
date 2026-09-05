# frozen_string_literal: true

# MASTER names tests test_<subject>.rb. RuleCoverageRule once globbed
# <base>_test.rb, found one file in 283, and reported a false positive about a
# test sitting right there.

root = File.expand_path("..", __dir__)
dir = File.join(root, "test")
wrong = Dir.glob(File.join(dir, "*_test.rb")).map { |path| File.basename(path) }
          .reject { |name| name.start_with?("test_") }
ok = Dir.glob(File.join(dir, "test_*.rb")).size

if wrong.empty?
  puts "test_naming: #{ok} test_*.rb, 0 *_test.rb"
  exit 0
end

wrong.each { |name| puts "  #{name}" }
abort "test_naming: #{wrong.size} file(s) use *_test.rb — MASTER's convention is test_*.rb"
