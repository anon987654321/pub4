# frozen_string_literal: true

# The repo's measuring code, held to answers a human wrote down.
#
# My measurement code is wrong more often than my reasoning, and a wrong
# instrument is expensive precisely because its output is plausible. On
# 2026-08-12 a hand-rolled method-length counter scored `def x = ...` as running
# to the next `end`, reported MASTER's longest method as 60 lines when it was
# 34, and made a tightly factored codebase look like it needed a refactor. On
# the same day a verification regex with broken escaping reported zero matches
# for a pattern that had two, which nearly got read as "the fold lost those
# edits".
#
# Neither was caught by a test. Both would have been caught in ten seconds by a
# file whose correct answers were already written down.
#
# So: tools/fixtures/*.rb each carry a header naming what they contain,
#
#     # instrument: code_lines=8 longest_method=1 public_methods=4
#
# and this runs the real implementations against them. The answers are declared
# by hand and the instrument is checked against the declaration — never the
# other way around, which would only prove the instrument agrees with itself.
#
# Point a new throwaway counter at these before trusting a number it produced.
#
#   ruby MASTER/tools/instruments.rb
#   ruby MASTER/tools/instruments.rb --json
#
# Wired as `rake lint:instruments`, pinned by test/test_instruments.rb.

require "json"

module Pub4
  class Instruments
    MASTER = File.expand_path("..", __dir__)
    FIXTURES = File.join(MASTER, "tools", "fixtures")
    HEADER = /^#\s*instrument:\s*(.+)$/

    def self.metrics
      @metrics ||= begin
        $LOAD_PATH.unshift(File.join(MASTER, "lib")) unless $LOAD_PATH.include?(File.join(MASTER, "lib"))
        require "master"
        Master::Review::Scan::CodeMetrics
      end
    end

    def self.fixtures
      Dir.glob(File.join(FIXTURES, "*.rb")).sort
    end

    def self.declared(source)
      line = source[HEADER, 1]
      return {} unless line

      line.split.to_h { |pair| key, value = pair.split("="); [key, Integer(value)] }
    end

    # Every measurement below comes from lib/, so this checks the shipped
    # implementation rather than a copy of it living next to the fixtures.
    def self.measured(source)
      lines = source.lines
      defs = def_nodes(source)
      { "code_lines" => metrics.code_lines(source),
        "namespace_lines" => metrics.namespace_lines(source),
        "longest_method" => defs.map { |node| metrics.method_code_lines(node, lines) }.max.to_i,
        "public_methods" => class_nodes(source).sum { |node| metrics.public_method_count(node) } }
    end

    def self.walk(source)
      require "prism"
      found = []
      visit = lambda do |node|
        return unless node.respond_to?(:child_nodes)

        found << node
        node.child_nodes.compact.each { |child| visit.call(child) }
      end
      visit.call(Prism.parse(source).value)
      found
    end

    def self.def_nodes(source) = walk(source).grep(Prism::DefNode)
    def self.class_nodes(source) = walk(source).grep(Prism::ClassNode)

    def self.run
      findings = []
      checks = 0

      fixtures.each do |path|
        source = File.read(path)
        declared_values = declared(source)
        name = File.basename(path)

        if declared_values.empty?
          findings << { "fixture" => name, "message" => "has no `# instrument:` header, so it declares nothing" }
          next
        end

        measured_values = measured(source)
        declared_values.each do |metric, expected|
          checks += 1
          actual = measured_values.fetch(metric, nil)
          next if actual == expected

          findings << { "fixture" => name, "metric" => metric, "declared" => expected, "measured" => actual,
                        "message" => "declares #{metric}=#{expected}, the implementation measures #{actual}" }
        end
      end

      { "fixtures" => fixtures.size, "checks" => checks, "findings" => findings }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  report = Pub4::Instruments.run

  if ARGV.include?("--json")
    puts JSON.pretty_generate(report)
  else
    report["findings"].each { |row| puts "#{row['fixture']}: #{row['message']}" }
    puts
    puts "#{report['checks']} declared answer(s) across #{report['fixtures']} fixture(s)"
    puts "instruments: #{report['findings'].empty? ? 'agree' : "#{report['findings'].size} disagreement(s)"}"
  end

  exit(report["findings"].empty? ? 0 : 1)
end
