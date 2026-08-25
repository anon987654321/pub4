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

    # The locale trees carry the only non-English prose in the repo, which is
    # what the nb laws in law/prose.rb judge. Without them those two load,
    # prove their fixtures, and reach no file — law that reads as enforcement
    # and enforces nothing, which is the defect this repo names most often.
    TREES = %w[
      MASTER/lib MASTER/law MASTER/tools RAILS/shared/lib RAILS/gates OPENBSD STUDIO
      RAILS/*/config/locales RAILS/*/engines/*/config/locales
    ].freeze

    module_function

    def law
      unless defined?(::Law)
        require File.join(MASTER_DIR, "lib", "master")
        require File.join(MASTER_DIR, "law", "law")
      end
      ::Law.load_all(File.join(MASTER_DIR, "law")) if ::Law.rules.empty?
      ::Law.rules
    end

    # Every extension a law can declare, not just Ruby. The corpus globbed
    # `*.rb` while the laws claim nine languages, so every css, scss, yaml,
    # markdown, html, json and shell law in the registry was measured against
    # nothing and reported clean: NULLISH_COALESCING, I18N_COVERAGE,
    # STRICT_LOADING_MISSING and META_CHARSET had 75 findings between them that
    # this tool could not see. A ratchet blind to two thirds of its subject
    # counts down to zero without the tree improving.
    # Globbed per extension rather than `**/*` filtered afterwards: STUDIO holds
    # the sample library, so walking every entry to stat it costs more than the
    # scan does. Memoized because `run` asks for the list twice.
    def files
      law # loads Master before FILE_LANGUAGE_MAP is read, as by_rule does
      @files ||= Master::FILE_LANGUAGE_MAP.keys
                                          .flat_map { |ext| TREES.flat_map { |t| Dir.glob(File.join(ROOT, t, "**", "*#{ext}")) } }
                                          .reject { |f| f.include?("/vendor/") || f.include?("/node_modules/") || f.include?("/assets/builds/") }
                                          .uniq
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
