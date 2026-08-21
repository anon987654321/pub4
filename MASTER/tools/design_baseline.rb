# frozen_string_literal: true

# The layout campaign's ratchet: MASTER's design rules measured over RAILS,
# per app, held by a ceiling that only descends.
#
# The 2026-08-21 campaign took the design findings from ~1,700 to the numbers
# in data/design_baseline.yml — part real fixes, part instruments learning what
# they judge (a tag is not a line; a media query bound is not a text measure).
# Without a committed tool reproducing the number, the next drift is invisible;
# this is the reader (see css_coverage_lint for the same argument about the
# register's unused-selector count).
#
#   cd MASTER && bundle exec ruby tools/design_baseline.rb            # measure
#   cd MASTER && bundle exec ruby tools/design_baseline.rb --ratchet  # record new low
#
# Wired into Pub4::Ratchets#deep_rows, so `bin/check --profile=full` holds it.
require "yaml"

module Pub4
  module DesignBaseline
    MASTER_ROOT = File.expand_path("..", __dir__)
    RAILS_ROOT = File.expand_path("../../RAILS", __dir__)
    CEILING = File.join(MASTER_ROOT, "data", "design_baseline.yml")

    # The rules that judge layout, markup shape, and typography — the set the
    # campaign measured. Info-tier markup-idiom rules (PREFER_TAG_HELPERS,
    # TAG_HELPER_OVER_MARKUP) are excluded: their thousand-finding backlog is
    # a campaign of its own and would drown movement in the rules that matter.
    DESIGN_RULES = %w[
      SEMANTIC_ELEMENTS MOBILE_FIRST NO_IMPORTANT MAGIC_COLOR MEASURE_OPTIMUM
      CLAMP_TYPOGRAPHY LOGICAL_PROPERTIES TYPOGRAPHY_DISCIPLINE
      TYPOGRAPHIC_EXCELLENCE ARIA_LABELS ARIA_INTERACTIVE IMG_ALT LAZY_IMAGES
      SKIP_TO_MAIN NO_LONG_TRANSITION REDUCED_MOTION ANTI_DIVITIS BEM_IN_VIEWS
      UTILITY_CLASS_SOUP NO_INLINE_STYLES HTML_LANG META_CHARSET
      BUTTON_OVER_ANCHOR CLASS_RESTATES_TAG BARE_DIV_WRAPPER
      PRESENTATIONAL_CLASS_NAME FORM_LABEL SINGLE_H1 TABINDEX_ABOVE_ZERO
      H1_VISIBILITY
    ].to_set

    module_function

    def counts
      scanner = build_scanner
      tally = Hash.new(0)
      files.each do |file|
        src = File.read(file, encoding: "UTF-8")
        app = app_for(file)
        scanner.rules.each do |rule|
          hits = begin
            rule.check(src, path: file) || []
          rescue StandardError
            []
          end
          hits.each do |hit|
            id = (hit.respond_to?(:[]) ? hit[:rule] : nil).to_s
            id = rule.id.to_s if id.empty? || id == "law_bridge"
            tally[app] += 1 if DESIGN_RULES.include?(id.upcase)
          end
        end
      end
      tally
    end

    def files
      Dir[File.join(RAILS_ROOT, "{brgen,amber,bsdports,shared}/app/{views,assets/stylesheets}/**/*.{erb,scss}")] +
        Dir[File.join(RAILS_ROOT, "brgen/engines/*/app/{views,assets/stylesheets}/**/*.{erb,scss}")]
    end

    def app_for(file)
      rel = file.sub("#{RAILS_ROOT}/", "")
      rel.include?("/engines/") ? "engines" : rel.split("/").first
    end

    def build_scanner
      $LOAD_PATH.unshift(File.join(MASTER_ROOT, "lib")) unless $LOAD_PATH.include?(File.join(MASTER_ROOT, "lib"))
      require "master"
      require "review/scan/rule_dsl"
      Master::Review::Scan::InfraHelpers.build_scanner(root: Master::ROOT)
    end

    def ceilings
      File.exist?(CEILING) ? (YAML.safe_load_file(CEILING) || {}) : {}
    end

    def run(ratchet: false)
      current = counts
      total = current.values.sum
      recorded = ceilings
      recorded_total = recorded.fetch("total", nil)

      puts "design_baseline: #{total} violation(s) (ceiling #{recorded_total || "unrecorded"})"
      current.sort.each { |app, count| puts "  #{app}: #{count} (ceiling #{recorded.dig("apps", app) || "-"})" }

      if ratchet
        File.write(CEILING, { "total" => total, "apps" => current.sort.to_h,
                              "rules" => DESIGN_RULES.sort }.to_yaml)
        puts "design_baseline: recorded #{total} as the new low"
        return true
      end

      recorded_total.nil? || total <= recorded_total
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit(Pub4::DesignBaseline.run(ratchet: ARGV.include?("--ratchet")) ? 0 : 1)
end
