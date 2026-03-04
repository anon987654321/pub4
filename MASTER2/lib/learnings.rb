# frozen_string_literal: true

require "time"

module Learnings
  DEFAULT_PRUNE_AGE_DAYS = 90
  PRUNE_BATCH_SIZE = 500
  MAX_SEED_ENTRIES = 1_000

  LOG_INFO = { severity: :info }.freeze
  LOG_WARN = { severity: :warn }.freeze

  module_function

  def apply_to(scope, fix:, actor: nil, at: nil)
    Applier.new(scope:, fix:, actor:, at: at || utc_now).call
  end

  def prune!(relation: Learning.all, older_than_days: DEFAULT_PRUNE_AGE_DAYS, at: nil)
    older_than = (at || utc_now) - (older_than_days * 86_400)
    Pruner.new(relation:, older_than:).call
  end

  def build_seed_entries(fixes:, limit: MAX_SEED_ENTRIES)
    SeedBuilder.new(fixes:, limit:).call
  end

  def extract_pattern_from_fix(fix)
    PatternExtractor.new(fix:).call
  end

  def utc_now
    time = Time.now.utc
    time
  end

  def utc_iso8601(time = utc_now)
    time.iso8601
  end

  class Applier
    def initialize(scope:, fix:, actor:, at:)
      @scope = scope
      @fix = fix
      @actor = actor
      @at = at
    end

    def call
      pattern = Learnings.extract_pattern_from_fix(@fix)
      return @scope unless pattern

      apply_scope(@scope, pattern)
    rescue StandardError => e
      Logging.warn("learnings.apply_to failed: #{e.class}: #{e.message}", **LOG_WARN)
      @scope
    end

    private

    def apply_scope(scope, pattern)
      return scope.where(pattern:) if scope.respond_to?(:where)

      scope
    rescue StandardError => e
      Logging.warn("learnings.apply_scope failed: #{e.class}: #{e.message}", **LOG_WARN)
      scope
    end
  end

  class Pruner
    def initialize(relation:, older_than:)
      @relation = relation
      @older_than = older_than
    end

    def call
      return 0 unless @relation

      prunable = base_relation
      return 0 unless prunable.respond_to?(:in_batches)

      deleted = 0
      prunable.in_batches(of: PRUNE_BATCH_SIZE) do |batch|
        deleted += delete_batch(batch)
      end
      deleted
    rescue StandardError => e
      Logging.warn("learnings.prune failed: #{e.class}: #{e.message}", **LOG_WARN)
      0
    end

    private

    def base_relation
      rel = @relation
      rel = rel.where("created_at < ?", @older_than) if rel.respond_to?(:where)
      rel
    rescue StandardError => e
      Logging.warn("learnings.prune base_relation failed: #{e.class}: #{e.message}", **LOG_WARN)
      @relation
    end

    def delete_batch(batch)
      return batch.delete_all if batch.respond_to?(:delete_all)

      0
    rescue StandardError => e
      Logging.warn("learnings.prune delete_batch failed: #{e.class}: #{e.message}", **LOG_WARN)
      0
    end
  end

  class SeedBuilder
    def initialize(fixes:, limit:)
      @fixes = fixes
      @limit = limit
    end

    def call
      fixes = preload(@fixes)
      return [] unless fixes

      entries = []
      each_fix(fixes) do |fix|
        entry = build_entry_for_fix(fix)
        next unless entry

        entries << entry
        break if entries.size >= @limit
      end

      entries
    rescue StandardError => e
      Logging.warn("learnings.build_seed_entries failed: #{e.class}: #{e.message}", **LOG_WARN)
      []
    end

    private

    def preload(fixes)
      return fixes.includes(:learnings, :author) if fixes.respond_to?(:includes)

      fixes
    rescue StandardError => e
      Logging.warn("learnings.build_seed_entries preload failed: #{e.class}: #{e.message}", **LOG_WARN)
      fixes
    end

    def each_fix(fixes, &block)
      return fixes.find_each(&block) if fixes.respond_to?(:find_each)

      Array(fixes).each(&block)
    end

    def build_entry_for_fix(fix)
      pattern = Learnings.extract_pattern_from_fix(fix)
      return nil unless pattern

      {
        fix_id: id_for(fix),
        pattern:,
        created_at: Learnings.utc_iso8601,
        meta: seed_meta(fix)
      }
    rescue StandardError => e
      Logging.warn("learnings.build_seed_entries build_entry_for_fix failed: #{e.class}: #{e.message}", **LOG_WARN)
      nil
    end

    def seed_meta(fix)
      {
        source: "seed",
        fix_class: fix.class.name,
        fix_ref: id_for(fix)
      }
    end

    def id_for(obj)
      return obj.id if obj.respond_to?(:id)

      obj.to_s
    end
  end

  class PatternExtractor
    def initialize(fix:)
      @fix = fix
    end

    def call
      return nil unless @fix

      raw = extract_raw(@fix)
      return nil if raw.nil? || raw.to_s.strip.empty?

      compile(raw.to_s)
    rescue StandardError => e
      Logging.warn("learnings.extract_pattern_from_fix failed: #{e.class}: #{e.message}", **LOG_WARN)
      nil
    end

    private

    def extract_raw(fix)
      return fix.pattern if fix.respond_to?(:pattern)
      return fix.regex if fix.respond_to?(:regex)
      return fix.text if fix.respond_to?(:text)

      nil
    end

    def compile(raw)
      Regexp.new(raw).source
    rescue StandardError => e
      Logging.warn("learnings.extract_pattern_from_fix compile failed: #{e.class}: #{e.message}", **LOG_WARN)
      nil
    end
  end
end