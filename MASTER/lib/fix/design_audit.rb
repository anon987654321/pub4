# frozen_string_literal: true

module Master
  module Fix
    # Design opportunities a rule scan cannot express: shape, not syntax. Each detector reads files and
    # returns Rows; OpportunityPass turns them into prompts for the ordinary Council and RepairLoop path,
    # so nothing here edits a file. A detector that guesses is capped and says what it saw, never what to do
    # without looking.
    module DesignAudit
      Row = Data.define(:file, :line, :message, :fix)

      # Same-named files must share this many method names, and this share of them, to count as one idea.
      SHARED_METHODS = 3
      SHARED_SHARE = 0.5

      # Below this, a test that reads source text is a contract on one fact, not a habit.
      SPELLING_MIN = 5
      SPELLING_SHARE = 0.6

      LOOP_START = /\.(?:each|map|flat_map|each_with_index|filter_map)\b.*\bdo\b|\.(?:each|map|flat_map)\s*\{/
      SPAWN = /\b(?:Exec\.capture\w*|Open3\.\w+|system)\(/
      LOOP_WINDOW = 12

      # File names that repeat by Ruby convention, one per namespace.
      CONVENTIONAL = %w[engine version base index railtie].freeze

      module_function

      def run(repo_root:)
        lib = File.join(repo_root, "MASTER", "lib")
        [duplicated_modules(lib, repo_root:), lone_directories(lib), spelling_tests(repo_root:),
         spawn_in_loops(lib)].flatten
      end

      # Two files of one name that also share most of their method names are one idea written twice. A shared
      # name alone is not evidence: Core::Proof and Convergence::Proof are different things in different places.
      def duplicated_modules(lib, repo_root:)
        groups = Dir.glob(File.join(lib, "**", "*.rb")).group_by { |path| File.basename(path, ".rb") }
        groups.reject { |name, paths| paths.size < 2 || CONVENTIONAL.include?(name) }.flat_map do |_name, paths|
          paths.combination(2).filter_map { |pair| duplicate_row(pair, repo_root:) }
        end
      end

      def duplicate_row(pair, repo_root:)
        first, second = pair.map { |path| method_names(path) }
        shared = first & second
        return if shared.size < SHARED_METHODS || shared.size < (first | second).size * SHARED_SHARE

        where = pair.map { |path| path.delete_prefix("#{repo_root}/") }.join(" and ")
        names = shared.first(4).join(", ")
        Row.new(pair.first, 1, "duplicated module: #{where} share #{shared.size} method names (#{names})",
                "Read both. Keep one implementation and make the other a thin caller or delete it; " \
                "check every caller and require before removing either.")
      end

      def method_names(path)
        File.read(path, encoding: "UTF-8").scan(/^\s*def (?:self\.)?([a-z_]\w*[?!]?)/).flatten.uniq
      end

      # lib/x/ holding one file beside lib/x.rb is a folder that earns nothing.
      def lone_directories(lib)
        Dir.glob(File.join(lib, "*", "")).filter_map do |dir|
          entries = Dir.children(dir)
          next unless entries.size == 1 && entries.first.end_with?(".rb")
          next unless File.file?("#{dir.chomp("/")}.rb")

          Row.new(File.join(dir, entries.first), 1,
                  "lone-file directory: #{File.basename(dir)}/ holds only #{entries.first}",
                  "Fold the file into #{File.basename(dir)}.rb or give the directory a second reason to exist. " \
                  "Check Zeitwerk and every require_relative before moving it.")
        end
      end

      # A test that mostly asserts on the text of source files breaks when code moves and proves little.
      def spelling_tests(repo_root:)
        tests = Dir.glob(File.join(repo_root, "{MASTER,RAILS,OPENBSD}", "**", "test*", "**", "*_test.rb")) +
                Dir.glob(File.join(repo_root, "MASTER", "test", "test_*.rb"))
        tests.uniq.filter_map { |path| spelling_row(path) }.first(8)
      end

      def spelling_row(path)
        text = File.read(path, encoding: "UTF-8")
        readers = text.scan(/^\s*(\w+)\s*=\s*File\.read\(/).flatten.uniq
        return if readers.empty?

        total = text.scan(/\bassert\w*\s/).size
        spelled = text.scan(/\bassert_(?:includes|match)\s+(?:#{readers.join("|")})\b/).size
        return if spelled < SPELLING_MIN || spelled < total * SPELLING_SHARE

        Row.new(path, 1, "spelling test: #{spelled} of #{total} assertions check the text of a source file",
                "Replace the text checks with a call that runs the code and asserts its result. Keep a text check " \
                "only where the spelling itself is the contract, such as a generated file.")
      end

      # A subprocess per item is the cost no one sees until the item count grows.
      def spawn_in_loops(lib)
        Dir.glob(File.join(lib, "**", "*.rb")).flat_map { |path| spawn_rows(path) }.first(8)
      end

      def spawn_rows(path)
        lines = File.readlines(path, encoding: "UTF-8")
        previous = -LOOP_WINDOW
        lines.each_index.filter_map do |index|
          next unless lines[index].match?(LOOP_START)
          next unless lines[index + 1, LOOP_WINDOW].any? { |line| line.match?(SPAWN) }
          next if index - previous < LOOP_WINDOW

          previous = index

          Row.new(path, index + 1, "subprocess per item: a loop here spawns a process on each pass",
                  "Run the tool once over the whole set and index its output, or cache by content. " \
                  "Measure before and after; keep the change only if it is faster.")
        end
      end
    end
  end
end
