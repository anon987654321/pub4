# frozen_string_literal: true

# Flags live schema foreign keys that point at phantom SQLite tables.

require_relative "../tools/utf8"

ROOT = File.expand_path("../..", __dir__)
PHANTOM_TABLES = %w[
  buyers listings likers likees dislikers dislikees initiators receivers orders menu_items
  followees followers followed
].freeze

def schema_files
  Dir.glob(File.join(ROOT, "DEPLOY", "rails", "*", "db", "schema.rb"))
end

def check_schema(path)
  text = File.read(path)
  text.scan(/add_foreign_key\s+"([^"]+)"\s*,\s*"([^"]+)"/).filter_map do |from, to|
    next unless PHANTOM_TABLES.include?(to)

    "#{path}: add_foreign_key #{from} → #{to} (phantom — use prefixed table or to_table:)"
  end
end

failures = schema_files.flat_map { |path| check_schema(path) }

if failures.empty?
  puts "phantom_foreign_keys: clean (#{schema_files.size} schemas)"
  exit 0
end

warn "phantom_foreign_keys: #{failures.size} issue(s):"
failures.each { |line| warn "  #{line}" }
exit 1
