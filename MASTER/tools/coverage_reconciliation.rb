# frozen_string_literal: true

# Coverage of the coverage: does every file the trees hold belong to at least
# one instrument that claims to see it?
#
# The repo's recurring blind spot is not a broken check but a check that
# silently stopped seeing part of the tree: 57 views fell out of four scanners
# when brgen's verticals became mountable engines, 10 stylesheets and 1,406
# lines sat outside every css_constitution ceiling for the same reason, and
# 1,513 more lines joined them when RAILS/master did. Each was found by hand,
# late, from prose. This tool makes the census computable instead.
#
#   ruby MASTER/tools/coverage_reconciliation.rb
#
# It reads checks/data/coverage_map.yml: the instruments that declare which
# globs they see. While the map declares itself partial (complete: false) the
# tool reports INCONCLUSIVE with the uncovered rows as information — a partial
# map that failed everything would be noise nobody routes through. When the
# map is declared complete, an uncovered file is a failure: either the file is
# out of scope on purpose (name it in the map's skip list, with a reason) or
# an instrument is blind again.
#
# The tri-state verdict matches the runner's vocabulary, so registering this
# as a script check later is a checks.yml row, not a redesign. It is not
# registered yet on purpose: it has not run on a Ruby host once, and a check
# with zero real runs is a hypothesis, not an instrument.

require "yaml"
require "set"
require_relative "../checks/support/check_result"

module Deploy
  class CoverageReconciliation
    DEFAULT_MAP = File.expand_path("../checks/data/coverage_map.yml", __dir__)
    DEFAULT_SKIP = %w[
      .git .bundle node_modules vendor tmp log coverage storage
      .master sockets pids cache builds public/builds
    ].freeze
    DIAGNOSTIC_LIMIT = 100

    attr_reader :uncovered

    def self.run(...) = new(...).run

    def initialize(map_path: DEFAULT_MAP, repo_root:, skip: DEFAULT_SKIP)
      @map_path = map_path
      @repo_root = File.expand_path(repo_root)
      @skip = skip
      @result = CheckResult.new
      @uncovered = []
    end

    def run
      @map = load_map or return @result
      instruments = Array(@map["instruments"])
      @result.checked!(instruments.size)

      covered = covered_set(instruments)
      inventory = inventory_set(Array(@map["roots"]))
      @uncovered = inventory.subtract(covered).sort

      @result.checked!(inventory.size)
      report(instruments, covered, inventory)
      @result
    rescue StandardError => e
      @result.inconclusive!("coverage_reconciliation: unreadable state (#{e.class}: #{e.message})")
      @result
    end

    private

    def load_map
      raise "map missing: #{@map_path}" unless File.file?(@map_path)

      map = YAML.safe_load_file(@map_path)
      raise "map has no instruments: #{@map_path}" unless map.is_a?(Hash) && map["instruments"].is_a?(Array)

      map
    rescue StandardError => e
      @result.inconclusive!("coverage_reconciliation: map unreadable (#{e.class}: #{e.message})")
      nil
    end

    def covered_set(instruments)
      instruments.flat_map do |row|
        Array(row["globs"]).map { |glob| Dir.glob(File.join(@repo_root, glob)) }.flatten
      end.map { |path| File.expand_path(path) }.to_set
    end

    def inventory_set(roots)
      roots.flat_map do |root|
        base = File.join(@repo_root, root)
        raise "inventory root missing: #{base}" unless Dir.exist?(base)

        Dir.glob(File.join(base, "**", "*"), File::FNM_DOTMATCH).select do |path|
          File.file?(path) && !path.split(File::SEPARATOR).any? { |part| @skip.include?(part) }
        end
      end.map { |path| File.expand_path(path) }.to_set
    end

    def report(instruments, covered, inventory)
      complete = @map["complete"] == true
      if complete && @uncovered.any?
        @uncovered.first(DIAGNOSTIC_LIMIT).each { |path| @result.fail("coverage: no instrument sees #{relative(path)}") }
        omitted = @uncovered.size - DIAGNOSTIC_LIMIT
        @result.fail("coverage: #{omitted} additional uncovered file(s) omitted") if omitted.positive?
      elsif complete
        @result.checked!(@uncovered.size)
      else
        @uncovered.first(DIAGNOSTIC_LIMIT).each { |path| @result.warn("coverage (partial map): no instrument sees #{relative(path)}") }
        @result.incomplete!(
          "coverage_reconciliation: map declares itself partial — #{instruments.size} instruments, " \
          "#{covered.size} files covered, #{inventory.size} in inventory, #{@uncovered.size} uncovered listed as information. " \
          "Fill the map, prove each row against its instrument on a Ruby host, then set complete: true."
        )
      end
    end

    def relative(path)
      path.delete_prefix("#{@repo_root}/")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  # The map's roots are repo-root relative (the directory holding MASTER and
  # RAILS); from MASTER/tools that is two levels up, not one.
  tool = Deploy::CoverageReconciliation.new(repo_root: File.expand_path("../..", __dir__))
  result = tool.run
  puts "coverage_reconciliation: #{result.outcome}, #{tool.uncovered.size} uncovered, " \
       "#{result.failures.size} fail, #{result.warnings.size} info"
  exit 1 if result.outcome == :failed
  exit 3 if result.outcome == :inconclusive
end
