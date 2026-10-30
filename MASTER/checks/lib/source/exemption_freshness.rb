# frozen_string_literal: true

require "date"
require "yaml"
require_relative "../../support/check_result"

module Deploy
  # Every exemption row in the craft ledger carries a review_by date, and until
  # this check existed that date was a human obligation: nothing failed when it
  # passed. The ledger's own header said so — "a stale_exemptions-style reader
  # is future work on a Ruby host". This is that reader, moved from obligation
  # to enforcement. It reads the ledger and the law files; it grants nothing
  # and skips nothing, exactly as the ledger's boundary #2 states: each Law's
  # path_exclude in data/laws.yml law_catalogue.entries decides what scanners skip.
  #
  # A row hard-fails when its review date has passed (the re-argument is
  # overdue — re-argue it or retire the exemption), when a promised field is
  # missing or its date is unparseable (an exemption without a date can never
  # expire, so it never gets re-argued), or when its law id names no
  # Law.define in any executable law file (the row documents an excuse whose
  # law no longer exists — dead evidence). A row warns when its law id is not
  # a top-level key of the canonical catalogue: AGENTS.md records that the
  # catalogue-to-executable mapping is still being reconciled through
  # LawRegistryAudit, so a catalogue absence is a known gap class, not a dead
  # row — the marker in law/ is what enforces. A row due within thirty days
  # warns, so the review lands on an operator calendar before it becomes a
  # failure. A missing ledger file is incomplete, never silently green.
  class ExemptionFreshnessCheck
    ROOT = File.expand_path("../../../..", __dir__)

    LEDGER = File.join(ROOT, "MASTER", "checks", "data", "craft_ledger.yml")
    CATALOGUE = File.join(ROOT, "MASTER", "data", "laws.yml")
    LAW_DIRS = %w[MASTER/law].freeze
    REQUIRED_FIELDS = %w[id law surface reason recorded review_by].freeze
    WARN_WINDOW_DAYS = 30

    def self.run(ledger_path: LEDGER, catalogue_path: CATALOGUE, law_root: ROOT)
      new(ledger_path:, catalogue_path:, law_root:).run
    end

    def initialize(ledger_path: LEDGER, catalogue_path: CATALOGUE, law_root: ROOT)
      @ledger_path = ledger_path
      @catalogue_path = catalogue_path
      @law_root = law_root
    end

    def run
      result = CheckResult.new
      unless File.file?(@ledger_path)
        return result.incomplete!("exemption_freshness: craft ledger not found at #{display(@ledger_path)}")
      end

      ledger = YAML.safe_load_file(@ledger_path)
      unless ledger.is_a?(Hash)
        return result.fail("exemption_freshness: #{display(@ledger_path)} is not a mapping — schema drift")
      end

      exemptions = ledger["exemptions"]
      exemptions = [] if exemptions.nil?
      unless exemptions.is_a?(Array)
        return result.fail("exemption_freshness: ledger exemptions section is not a list — schema drift")
      end

      return result.checked!(0) if exemptions.empty?

      catalogue_keys = catalogue_ids
      markers = marker_text

      exemptions.each_with_index { |row, index| review(result, row, index, catalogue_keys, markers) }
      result.checked!(exemptions.count)
      result
    end

    private

    def review(result, row, index, catalogue_keys, markers)
      row = {} unless row.is_a?(Hash)
      label = row["id"].to_s.strip.empty? ? "exemptions[#{index}]" : row["id"].to_s

      missing = REQUIRED_FIELDS.reject { |field| row[field].to_s.strip.length.positive? }
      unless missing.empty?
        result.fail("exemption_freshness: #{label} is missing #{missing.join(', ')} — an exemption without these can never be re-argued")
        return
      end

      due = parse_date(row["review_by"])
      if due.nil?
        result.fail("exemption_freshness: #{label} review_by #{row['review_by'].inspect} is not a date")
        return
      end

      days = (due - today).to_i
      if days.negative?
        result.fail("exemption_freshness: #{label} review was due #{due} (#{-days} days overdue) — re-argue the exemption against its law or retire it")
      elsif days <= WARN_WINDOW_DAYS
        result.warn("exemption_freshness: #{label} review due #{due} — put it on an operator calendar now")
      end

      law_id = row["law"].to_s
      unless markers.include?(law_id)
        result.fail("exemption_freshness: #{label} names law #{law_id}, which no executable law file declares — the row documents an excuse that no longer exists")
      end

      return if catalogue_keys.include?(law_id)
        result.warn("exemption_freshness: #{label} law #{law_id} is not a catalogue key in #{display(@catalogue_path)} — a known reconciliation gap (LawRegistryAudit), the marker in law/ is what enforces")

    end

    def catalogue_ids
      return [] unless File.file?(@catalogue_path)

      catalogue = YAML.safe_load_file(@catalogue_path)
      catalogue.is_a?(Hash) ? catalogue.keys.compact.map(&:to_s) : []
    rescue StandardError
      []
    end

    # The executable law home is law/, one flat directory,
    # the tree synonyms.yml names as executable_laws. Substring membership is
    # deliberately coarse: the marker may sit in a Law.define symbol, a
    # path_exclude comment or a registry entry, and which of those it is does
    # not change whether the law exists.
    def marker_text
      LAW_DIRS.filter_map { |dir| File.join(@law_root, dir) }
              .select { |dir| File.directory?(dir) }
              .flat_map { |dir| Dir.glob(File.join(dir, "**", "*.rb")) }
              .map { |path| File.read(path) }
              .join("\n")
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def today
      Date.today
    end

    def display(path)
      path.to_s.sub("#{ROOT}/", "")
    end
  end
end
