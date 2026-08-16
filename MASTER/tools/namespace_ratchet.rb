# frozen_string_literal: true

# Files that declare no module or class, counted, and allowed only to fall.
#
# STUDIO/dilla/lib/engine is 76 of 79 files with no namespace at all — 863
# methods defined directly on Object. That flatness is why a method could be
# called from one committed file and defined in another that was never
# committed, with nothing to break at load: there is no import to fail. It is
# also why the tree needs a bespoke test asking whether methods are called,
# which a module boundary answers for free.
#
#   ruby MASTER/tools/namespace_ratchet.rb
#   ruby MASTER/tools/namespace_ratchet.rb --ratchet
#
# Ratchets rather than demands. A wholesale refactor of 863 methods is not a
# patch anyone should take in one go; recording the number and refusing to let
# it rise makes every new file a module and every merge progress. Same mechanism
# as lint:spine, which has already refused a raise and forced a real deletion.

require "yaml"
require "json"

module Pub4
  module NamespaceRatchet
    CEILINGS = File.expand_path("../data/namespace_ceilings.yml", __dir__)
    ROOT = File.expand_path("../..", __dir__)

    module_function

    def flat_files(dir)
      Dir.glob(File.join(ROOT, dir, "**", "*.rb"))
         .reject { |path| path.match?(%r{/(vendor|node_modules|\.git|tmp)/}) }
         .reject { |path| File.read(path).match?(/^\s*(module|class)\s+[A-Z]/) }
    end

    def ceilings = File.exist?(CEILINGS) ? YAML.safe_load_file(CEILINGS) : {}

    def measure = ceilings.keys.to_h { |dir| [dir, flat_files(dir).size] }

    def run(ratchet: false, json: false)
      recorded = ceilings
      actual = measure
      over = actual.select { |dir, count| count > recorded[dir] }
      under = actual.select { |dir, count| count < recorded[dir] }

      return puts(JSON.pretty_generate(recorded:, actual:)) if json

      actual.each { |dir, count| puts format("  %-34s %3d flat file(s), ceiling %d", dir, count, recorded[dir]) }
      return record(actual) if ratchet && under.any?

      report(over, under)
    end

    def record(actual)
      File.write(CEILINGS, actual.to_yaml)
      puts "namespace_ratchet: recorded #{actual.values.sum} as the new low"
      0
    end

    def report(over, under)
      over.each { |dir, count| puts "namespace_ratchet: #{dir} rose to #{count} — a new file without a module" }
      under.each { |dir, count| puts "namespace_ratchet: #{dir} is #{count}, below its ceiling — run --ratchet" }
      over.empty? ? 0 : 1
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit Pub4::NamespaceRatchet.run(ratchet: ARGV.include?("--ratchet"), json: ARGV.include?("--json"))
end
