# frozen_string_literal: true

# What MASTER's own rules find in MASTER's own tree.
#
# The question "would running MASTER through its own rules make it tidier" has a
# number, and this is it. Every rule with a lexical detector, over every tracked
# Ruby file in the four trees.
#
# Lexical only, on purpose. The full gate runs /scan with the semantic pass and
# blocks on a model call — measured 2026-08-25 at 17 minutes elapsed against 4
# minutes of CPU, idle in a TLS read, on its way to a 20-minute stage timeout.
# A number that needs a network and an API key is a number nobody has. These 70
# rules need neither and finish in about a minute.
#
#   ruby MASTER/tools/self_findings.rb
#   ruby MASTER/tools/self_findings.rb --json

require "json"

module Pub4
  module SelfFindings
    MASTER_DIR = File.expand_path("..", __dir__)
    ROOT = File.expand_path("..", MASTER_DIR)
    CEILING = File.join(MASTER_DIR, "data", "self_findings.yml")

    TREES = %w[MASTER/lib MASTER/law MASTER/tools RAILS/shared/lib RAILS/gates OPENBSD STUDIO].freeze

    module_function

    def law
      unless defined?(::Law)
        require File.join(MASTER_DIR, "lib", "master")
        require File.join(MASTER_DIR, "law", "law")
      end
      ::Law.load_all(File.join(MASTER_DIR, "law")) if ::Law.rules.empty?
      ::Law.rules
    end

    def files
      TREES.flat_map { |t| Dir.glob(File.join(ROOT, t, "**", "*.rb")) }
           .reject { |f| f.include?("/vendor/") || f.include?("/node_modules/") }
           .sort
    end

    # A law file necessarily contains the pattern it forbids — in its detector,
    # its fix line and its bad fixture. Law.scan neutralises those before a law
    # judges law/; this file called rule.scan directly and skipped it, so all 35
    # findings under law/ were laws quoting themselves. With conduct applied it
    # is 0, which is the honest number: those lines declare evidence.
    def considered(path, text)
      path.include?("/MASTER/law/") ? ::Law.conduct(text) : text
    end

    def by_rule
      rules = law # loads Master before the map below is read
      counts = Hash.new(0)
      files.each do |path|
        text = considered(path, File.read(path, encoding: "UTF-8").scrub)
        lang = Master::FILE_LANGUAGE_MAP[File.extname(path)]&.to_sym
        rules.each_value do |rule|
          next if rule.semantic? || !rule.applies?(path, lang)

          counts[rule.id.to_s] += rule.scan(text, file: path).size
        end
      end
      counts.reject { |_, v| v.zero? }.sort_by { |_, v| -v }.to_h
    end

    def ceiling = YAML.safe_load_file(CEILING).fetch("findings")

    def run(json: false)
      counts = by_rule
      total = counts.values.sum
      return (puts JSON.pretty_generate(total: total, by_rule: counts)) || true if json

      puts "self_findings: #{total} across #{files.size} files from #{law.size} rules"
      counts.first(10).each { |id, n| puts format("  %-26s %5d", id, n) }
      over = total > ceiling
      warn "self_findings: exceeds baseline — #{total} > #{ceiling}" if over
      !over
    end
  end
end

require "yaml"

if $PROGRAM_NAME == __FILE__
  ok = Pub4::SelfFindings.run(json: ARGV.include?("--json"))
  exit(ok ? 0 : 1)
end
