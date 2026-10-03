# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "prism"
require "timeout"

require_relative "../lib/review/challenges"

module Master
  module Review
    module ChallengeTools
      ROOT = File.expand_path("../..", __dir__)

      class DeletionProbe
        Result = Data.define(:baseline_ok, :methods, :survivors, :errors)

        def initialize(test_path, root: ROOT)
          @test_path = File.expand_path(test_path, root)
          @root = File.expand_path(root)
        end

        def call
          original = File.read(@test_path)
          methods = method_ranges(original)
          baseline_ok, = run_test
          return Result.new(baseline_ok: false, methods: methods.map(&:first), survivors: [], errors: ["baseline test failed"]) unless baseline_ok

          survivors = []
          errors = []

          methods.each do |name, range|
            mutated = original.dup
            mutated[range] = ""
            begin
              File.write(@test_path, mutated)
              ok, output = run_test
              survivors << name if ok
              errors << "#{name}: #{output.lines.last.to_s.strip}" unless ok || output.empty?
            rescue StandardError => e
              errors << "#{name}: #{e.class}: #{e.message}"
            ensure
              File.write(@test_path, original)
            end
          end

          Result.new(baseline_ok: true, methods: methods.map(&:first), survivors:, errors:)
        ensure
          File.write(@test_path, original) if original
        end

        private

        def method_ranges(source)
          tree = Prism.parse(source).value
          found = []
          visit = lambda do |node|
            if node.is_a?(Prism::DefNode) && node.name.to_s.start_with?("test_")
              found << [node.name.to_s, node.location.start_offset...node.location.end_offset]
            end
            node.child_nodes.each { |child| visit.call(child) if child }
          end
          visit.call(tree)
          found.uniq
        rescue StandardError => e
          raise "could not parse #{@test_path}: #{e.class}: #{e.message}"
        end

        def run_test
          stdout = +""
          status = nil
          Timeout.timeout(Integer(ENV.fetch("MASTER_TEST_DELETION_TIMEOUT", "90"))) do
            stdout, status = Open3.capture2e(
              RbConfig.ruby, "-Ilib", "-Itest", @test_path,
              chdir: @root
            )
          end
          [status.success?, stdout]
        rescue Timeout::Error
          [false, "test process timed out"]
        end
      end

      module_function

      def deletion_probe(path)
        result = DeletionProbe.new(path).call
        {
          baseline_ok: result.baseline_ok,
          methods: result.methods,
          survivors: result.survivors,
          errors: result.errors
        }
      end

      def history(limit: 20)
        pattern = "fix|bug|regress|regression|restore|broken|repair|incident"
        out, status = Open3.capture2e(
          "git", "-C", ROOT, "log", "--all",
          "--regexp-ignore-case", "--grep=#{pattern}",
          "--format=%H%x09%s", "-n", limit.to_i.to_s
        )
        raise "git history query failed: #{out.lines.first.to_s.strip}" unless status.success?

        rows = out.lines.filter_map do |line|
          sha, subject = line.chomp.split("\t", 2)
          next unless sha && subject

          changed, changed_status = Open3.capture2e(
            "git", "-C", ROOT, "show", "--format=", "--name-only", sha
          )
          next unless changed_status.success?

          tests = changed.lines.map(&:strip).select { |path| path.match?(%r{(^|/)test/|(^|/)spec/}) }
          { sha:, subject:, tests: tests.uniq }
        end

        rows
      end

      def balance(root: ROOT)
        lib = Dir[File.join(root, "lib/**/*.rb")]
        tests = Dir[File.join(root, "test/test_*.rb")]
        direct = tests.to_h { |path| [File.basename(path).delete_prefix("test_").sub(/\.rb\z/, ""), true] }
        covered = lib.count { |path| direct.key?(File.basename(path, ".rb")) }
        large = lib.filter_map do |path|
          bytes = File.size(path)
          [path.delete_prefix(root + "/"), bytes] if bytes >= 20_000
        end.sort_by { |_, bytes| -bytes }

        {
          ruby_files: lib.size,
          test_files: tests.size,
          direct_test_name_matches: covered,
          direct_test_ratio: lib.empty? ? 1.0 : (covered.to_f / lib.size),
          large_ruby_files: large.first(25)
        }
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = { mode: "pack", test: nil, limit: 20, evidence: nil }
  OptionParser.new do |opts|
    opts.on("--mode MODE", %w[pack delete history balance]) { |v| options[:mode] = v }
    opts.on("--test PATH") { |v| options[:test] = v }
    opts.on("--limit N", Integer) { |v| options[:limit] = v }
    opts.on("--evidence TEXT") { |v| options[:evidence] = v }
  end.parse!(ARGV)

  case options[:mode]
  when "pack"
    evidence = options[:evidence] || STDIN.read
    puts Master::Review::Challenges.prompt(scope: :operator, evidence:)
  when "delete"
    abort "--test PATH is required for --mode delete" unless options[:test]
    puts JSON.pretty_generate(Master::Review::ChallengeTools.deletion_probe(options[:test]))
    exit 1 if Master::Review::ChallengeTools.deletion_probe(options[:test])[:survivors].any?
  when "history"
    rows = Master::Review::ChallengeTools.history(limit: options[:limit])
    rows.each do |row|
      puts "history0: #{row[:sha][0, 12]} #{row[:subject]}"
      if row[:tests].empty?
        puts "history0:   no test file changed — candidate for regression fixture mining"
      else
        row[:tests].each { |path| puts "history0:   #{path}" }
      end
    end
  when "balance"
    puts JSON.pretty_generate(Master::Review::ChallengeTools.balance)
  end
end
