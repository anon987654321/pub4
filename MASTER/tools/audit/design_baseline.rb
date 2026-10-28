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
#   cd MASTER && bundle exec ruby tools/audit/design_baseline.rb            # measure
#   cd MASTER && bundle exec ruby tools/audit/design_baseline.rb --ratchet  # record new low
#
# Wired into Operator::Ratchets#deep_rows, so `bin/check --profile=full` holds it.
require "yaml"
require_relative "../../lib/trace/dmesg"
require_relative "../../checks/support/fleet"

module Operator
  module DesignBaseline
    MASTER_ROOT = File.expand_path("../..", __dir__)
    RAILS_ROOT = File.expand_path("../../../RAILS", __dir__)
    CEILING = File.join(MASTER_ROOT, "data", "design_baseline.yml")

    # The Laws that judge layout, markup shape and typography: the baseline's
    # rule_ceilings, the one list of them. Info-tier markup-idiom Laws
    # (PREFER_TAG_HELPERS, TAG_HELPER_OVER_MARKUP) stay out: their thousand-finding
    # backlog would drown movement in the Laws that matter.
    DESIGN_RULES = YAML.safe_load_file(CEILING).fetch("rule_ceilings").to_set.freeze

    module_function

    def counts
      laws = deterministic_laws
      tally = Hash.new(0)
      files.each do |file|
        src = File.read(file, encoding: "UTF-8")
        app = app_for(file)
        laws.each do |rule|
          hits = begin
            rule.check(src, path: file) || []
          rescue StandardError => e
            # A broken rule must not silently shrink the baseline: the scan
            # continues, the breakage is on the record.
            warn "design_baseline: #{rule.id} raised on #{file}: #{e.class}"
            []
          end
          hits.each do |hit|
            id = (hit.respond_to?(:[]) ? hit[:law] : nil).to_s
            id = rule.id.to_s if id.empty?
            tally[app] += 1 if DESIGN_RULES.include?(id.upcase)
          end
        end
      end
      tally
    end

    # Every DESIGN_RULES law is deterministic. A model law here has no agent and could only
    # raise INCONCLUSIVE on every file, which no design count reads.
    def deterministic_laws
      laws = build_scanner.laws.reject { |rule| Master::Fix::Scan::UnmodelledTier.unmodelled?(rule) }
      validate_rule_ceilings!(laws)
      laws
    end

    # A stale ID in rule_ceilings must not make a design Law disappear and
    # lower the measured count. Membership is validated before the baseline
    # can report a total or ratchet a new one.
    def validate_rule_ceilings!(laws, expected: DESIGN_RULES)
      available = laws.map { |law| law.id.to_s.upcase }.to_set
      missing = expected.map { |id| id.to_s.upcase }.to_set - available
      unless missing.empty?
        raise ArgumentError,
              "design_baseline: rule_ceilings references missing or non-deterministic Laws: #{missing.to_a.sort.join(', ')}"
      end

      true
    end

    def files
      # The shared engine is named __shared, not "shared", and plain .css is
      # source too. Build this list from Fleet's source roots so the baseline
      # cannot silently omit the chrome every app mounts.
      surfaces = Fleet.asset_roots.flat_map do |surface|
        Dir[File.join(RAILS_ROOT, surface, "app/views/**/*.erb")] +
          Dir[File.join(RAILS_ROOT, surface, "app/assets/stylesheets/**/*.{scss,css}")]
      end
      engines = Fleet.asset_roots.flat_map do |surface|
        Dir[File.join(RAILS_ROOT, surface, "engines/*/app/views/**/*.erb")] +
          Dir[File.join(RAILS_ROOT, surface, "engines/*/app/assets/stylesheets/**/*.{scss,css}")]
      end
      # The MASTER face is the fourth public surface: its hand-written CSS and
      # chat views belong in the same instrument; generated bundles stay out.
      surfaces + engines +
        Dir[File.join(RAILS_ROOT, "master/app/views/**/*.erb")] +
        %w[face.css chat_upload.css].map { |name| File.join(RAILS_ROOT, "master/public", name) }.select { |f| File.file?(f) }
    end

    def app_for(file)
      return "face" if file.start_with?(File.join(RAILS_ROOT, "master"))
      rel = file.sub("#{RAILS_ROOT}/", "")
      rel.include?("/engines/") ? "engines" : rel.split("/").first
    end

    def build_scanner
      $LOAD_PATH.unshift(File.join(MASTER_ROOT, "lib")) unless $LOAD_PATH.include?(File.join(MASTER_ROOT, "lib"))
      require "master"
      require "review/scan/law_dsl"
      Master::Fix::Scanner.build(root: Master::ROOT)
    end

    def ceilings
      File.exist?(CEILING) ? (YAML.safe_load_file(CEILING) || {}) : {}
    end

    def run(ratchet: false)
      current = counts
      total = current.values.sum
      recorded = ceilings
      recorded_total = recorded.fetch("total", nil)

      Master::Trace::Dmesg.attach("design0", "master0", "#{total} violation(s), ceiling #{recorded_total || "unrecorded"}")
      current.sort.each { |app, count| Master::Trace::Dmesg.status("design0", "#{app}, #{count}, ceiling #{recorded.dig("apps", app) || "unrecorded"}") }

      # The machine-readable verdict line, last. Two consumers match it — the
      # ratchet stage's /design_baseline: (\d+) violation/ and check_chain's
      # verdict scan, which takes the last bare "name:" line — and a7a8cf4b8
      # dropped it in favour of the dmesg detail above, leaving both reading
      # the current count as "?" and the ratchet row unreadable.
      puts "design_baseline: #{total} violation(s) (ceiling #{recorded_total || "unrecorded"})"

      if ratchet
        File.write(CEILING, { "total" => total, "apps" => current.sort.to_h,
                              "rule_ceilings" => DESIGN_RULES.sort }.to_yaml)
        Master::Trace::Dmesg.status("design0", "recorded #{total} as the new low")
        return true
      end

      recorded_total.nil? || total <= recorded_total
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit(Operator::DesignBaseline.run(ratchet: ARGV.include?("--ratchet")) ? 0 : 1)
end
