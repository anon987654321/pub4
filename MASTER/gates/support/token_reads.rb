# frozen_string_literal: true

require_relative "gate_result"

module Deploy
  # The token map as the gates read it, with every read that found nothing
  # written down. A gate asks `@rules.dig("typography", "hierarchy", ...)` and
  # turns nil into zero, and a zero threshold is a check that returns early: the
  # whole typography block was absent from tokens.yml and caps tracking, the
  # weight ladder and the family count each passed by measuring nothing. The
  # runner asks this module at the end of the ladder, and a read the operator
  # has not declared unset fails it, so a key that leaves the file is reported
  # on the run in which it left.
  module TokenReads
    # Keys a gate reads and the operator has not set, each with the reason it
    # stands open. Setting one in tokens.yml means deleting its line here; an
    # entry that resolves is reported as stale.
    UNSET = {
      "typography.line_height.body_min" =>
        "DesignMetricsGate holds every line-height in its sample to it, headings included, and the scale allows 1 and 1.25",
      "typography.line_height.body_accessibility_min" => "no reader, test or sibling constant states a value",
      "typography.rag" => "GeometryType reads worn_type for the profile and falls back to its own two numbers here",
    }.freeze

    # Hash#dig on a nested value returns a plain Hash, so only a read that
    # starts at the map is seen. Every gate reads that way.
    class Map < Hash
      def initialize(values = {}, path = [])
        super()
        @path = path
        values.each do |key, value|
          self[key] = wrap_value(value, @path + [key])
        end
      end

      # Track direct bracket reads as well as dig. Nested hashes and hashes
      # inside arrays stay wrapped, carrying their full path so a miss is
      # reported as typography.hierarchy.some_key, not just some_key.
      def [](key)
        value = super
        TokenReads.note(@path + [key], found: !value.nil?)
        value
      end

      def dig(*path)
        value = super
        TokenReads.note(@path + path, found: !value.nil?)
        value
      end

      private

      def wrap_value(value, path)
        case value
        when Hash
          self.class.new(value, path)
        when Array
          value.each_with_index.map { |item, index| wrap_value(item, path + [index]) }
        else
          value
        end
      end
    end

    @reads = {}

    module_function

    def wrap(blocks) = Map.new(blocks.to_h)

    def note(path, found:)
      key = path.map(&:to_s).join(".")
      @reads[key] = found || @reads[key] == true
    end

    def reset! = @reads.clear

    def missed = @reads.reject { |_key, found| found }.keys.sort

    def undeclared = missed - UNSET.keys

    def stale = UNSET.keys.select { |key| @reads[key] == true }.sort

    # One result for the ladder: a failure per undeclared miss and per stale
    # declaration, a warning per declared one, and a count of what was read.
    def result
      report = GateResult.new
      return report.inconclusive!("token_reads: no gate read the token map") if @reads.empty?

      report.checked!(@reads.size)
      undeclared.each do |key|
        report.fail("token_reads: a gate read #{key} and tokens.yml has no such key; the check that needs it measured nothing")
      end
      stale.each { |key| report.fail("token_reads: #{key} is set in tokens.yml and still declared unset in TokenReads::UNSET") }
      (missed & UNSET.keys).each { |key| report.warn("token_reads: #{key} unset: #{UNSET.fetch(key)}") }
      report
    end
  end
end
