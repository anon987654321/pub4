# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  class PhantomForeignKeysGate
    ROOT = File.expand_path("../../../..", __dir__)
    PHANTOM_TABLES = %w[
      buyers listings likers likees dislikers dislikees initiators receivers orders menu_items
      followees followers followed
    ].freeze

    def self.run
      new.run
    end

    def run
      result = GateResult.new
      files = Dir.glob(File.join(ROOT, "RAILS", "*", "db", "schema.rb"))
      files.each do |path|
        File.read(path).scan(/add_foreign_key\s+"([^"]+)"\s*,\s*"([^"]+)"/).each do |from, to|
          next unless PHANTOM_TABLES.include?(to)

          result.fail("#{path}: add_foreign_key #{from} → #{to} (phantom — use prefixed table or to_table:)")
        end
      end
      result
    end
  end
end
