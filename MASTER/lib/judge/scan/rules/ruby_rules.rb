# frozen_string_literal: true

module Master
  module Judge
  module Scan
  module Rules

  RuleDSL.rule :SINGLE_PRIVATE_SECTION,
    severity: :info, tags: %i[SMALL_PARTS], applies_to: %i[ruby],
    description: "one private section at bottom" do |src, path:|
    scan_lines(src, /private\s+:\w+/, message: "inline private call — gather private methods at bottom")
  end

  RuleDSL.rule :STRICT_LOADING_MISSING,
    severity: :info, tags: %i[PERFORMANCE], applies_to: %i[ruby],
    description: "AR model lacks strict_loading_by_default" do |src, path:|
    next [] unless path.include?("/app/models/")
    next [] if src.match?(/\bstrict_loading_by_default\b/)
    next [] unless src.match?(/class\s+\w+\s+<\s+(?:ApplicationRecord|ActiveRecord::Base)\b/)
    [finding(line: 1, message: "model missing strict_loading_by_default true")]
  end

  RuleDSL.rule :RATE_LIMITING_MISSING,
    severity: :error, tags: %i[SECURITY], applies_to: %i[ruby],
    description: "sensitive controller missing rate_limit/throttle" do |src, path:|
    next [] unless path.include?("/app/controllers/")
    next [] if src.match?(/rate_limit|throttle/)
    next [] unless src.match?(/(login|signup|sign_up|password|reset)/)
    [finding(line: 1, message: "auth/sensitive controller missing rate_limit or throttle")]
  end

  RuleDSL.rule :MIGRATION_ADD_REFERENCE_NO_FK,
    severity: :error, tags: %i[DATA_INTEGRITY], applies_to: %i[ruby],
    description: "add_reference without foreign_key:" do |src, path:|
    next [] unless path.include?("/db/migrate/")
    scan_lines(src, /add_reference(?!.*foreign_key:)/,
      message: "add_reference without foreign_key: true — data integrity risk")
  end

  RuleDSL.rule :MIGRATION_REMOVE_COLUMN,
    severity: :error, tags: %i[DATA_INTEGRITY], applies_to: %i[ruby],
    description: "remove_column is destructive" do |src, path:|
    next [] unless path.include?("/db/migrate/")
    scan_lines(src, /remove_column/,
      message: "remove_column is destructive — confirm column is unused across all deploys")
  end

  RuleDSL.rule :MIGRATION_FIND_OR_CREATE_BY,
    severity: :warning, tags: %i[DATA_INTEGRITY], applies_to: %i[ruby],
    description: "find_or_create_by needs unique index" do |src, path:|
    next [] unless path.include?("/db/migrate/")
    scan_lines(src, /find_or_create_by/, message: "find_or_create_by is not atomic without a unique index")
  end

  RuleDSL.rule :EACH_WITH_OBJECT,
    severity: :warning, tags: %i[READABILITY], applies_to: %i[ruby],
    description: "prefer each_with_object over inject for hash building" do |src, path:|
    scan_lines(src, /\.(inject|reduce)\(\s*\{\s*\}\s*\)/, message: "use each_with_object({}) over inject({})")
  end

  RuleDSL.rule :KERNEL_COERCION,
    severity: :info, tags: %i[READABILITY], applies_to: %i[ruby],
    description: "use Array(), Hash(), String() coercions" do |src, path:|
    next [] if path.to_s.include?("/judge/scan/rules/")
    scan_lines(src, /(\w+)\s*\|\|\s*\[\](?!\s*<<)/,
      message: "nil-or-empty array — prefer Array(foo) for nil-safe coercion")
  end

  RuleDSL.rule :PERCENT_LITERAL,
    severity: :info, tags: %i[READABILITY], applies_to: %i[ruby],
    description: "use %i[] and %w[] for symbol/string arrays" do |src, path:|
    scan_lines(src, /\[:[a-z_]+,\s*:[a-z_]+,\s*:[a-z_]+/,
      message: "use %i[...] for symbol arrays")
  end

  RuleDSL.rule :HASH_FETCH,
    severity: :info, tags: %i[READABILITY], applies_to: %i[ruby],
    description: "prefer Hash#fetch over [] with ||" do |src, path:|
    next [] if path.to_s.include?("/judge/scan/rules/")
    scan_lines(src, /\w+\[:\w+\]\s*\|\|/,
      message: "hash symbol lookup with fallback — prefer hash.fetch(:key, default)")
  end

  RuleDSL.rule :TRANSFORM_KEYS,
    severity: :info, tags: %i[READABILITY], applies_to: %i[ruby],
    description: "use transform_keys/transform_values" do |src, path:|
    scan_lines(src, /\.each_with_object\(\{\}\)\s*\{\s*\|\(k,\s*v\),\s*h\|/,
      message: "use transform_keys/transform_values instead of manual each_with_object")
  end

  RuleDSL.rule :IMMUTABLE,
    severity: :info, tags: %i[PERFORMANCE], applies_to: %i[ruby],
    description: "default to immutable data" do |src, path:|
    src.each_line.with_index(1).filter_map do |line, n|
      next unless line.match?(/^\s*[A-Z][A-Z_]*\s*=\s*[\[{].*[\]}]/)
      next if line.match?(/\.freeze/)
      finding(line: n, message: "mutable constant — append .freeze")
    end
  end

  RuleDSL.rule :FIND_EACH,
    severity: :warning, tags: %i[PERFORMANCE], applies_to: %i[ruby],
    description: "use find_each for batch processing" do |src, path:|
    next [] unless path.match?(%r{/app/|/spec/|/test/})
    scan_lines(src, /\.(all\.each|where\(.*\)\.each)\b/,
      message: "unbounded .all.each — use find_each(batch_size: N)")
  end

  RuleDSL.rule :NO_UPDATE_ATTRIBUTE,
    severity: :error, tags: %i[DATA_INTEGRITY], applies_to: %i[ruby],
    description: "replace update_attribute with update!" do |src, path:|
    next [] unless path.match?(%r{/app/|/spec/|/test/})
    scan_lines(src, /\.update_attribute\(/, message: "update_attribute skips validations — use update!")
  end

  RuleDSL.rule :PLUCK_OVER_MAP,
    severity: :info, tags: %i[PERFORMANCE], applies_to: %i[ruby],
    description: "prefer pluck over map for single columns" do |src, path:|
    next [] unless path.match?(%r{/app/|/spec/|/test/})
    scan_lines(src, /\.\w+\.map\(&:\w+\)/, message: "use pluck(:column) to avoid loading full objects")
  end

  end
  end
  end
end
