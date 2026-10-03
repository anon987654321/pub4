# frozen_string_literal: true

require_relative "master_design"

require "set"
require_relative "../lib/trace/dmesg"

module Operator
  # Validates every spacing-tagged value in MASTER's tokens and every --space
  # custom property a stylesheet defines, in shared, each app and each engine
  # (a token defined beside the view it serves is still a token), against MASTER's own
  # laws.yml design_rules.pixel_perfection.eight_px_rhythm allowlist. Reads that
  # allowlist from MASTER directly rather than duplicating it, so the two
  # can never drift apart through a second machine-readable authority
  # (the --color-warning bug found 2026-07-21).
  module RhythmLint
    SPACE_KEY = /\Aspace[_-]/i
    SPACE_CSS_VAR = /--([\w-]*space[\w-]*)\s*:\s*([\d.]+)(rem|px)\s*;/i

    Violation = Struct.new(:source, :name, :value_px)

    module_function

    def run
      rules = load_design_rules
      unless rules
        Master::Trace::Dmesg.status("rhythm0", "could not find MASTER/data/laws.yml, skipped", io: $stderr)
        return true
      end

      allowed = rules.dig("pixel_perfection", "eight_px_rhythm")
      unless allowed
        Master::Trace::Dmesg.status("rhythm0", "design rules have no pixel_perfection.eight_px_rhythm, skipped", io: $stderr)
        return true
      end
      allowed = allowed.map(&:to_i).to_set

      violations = []
      violations.concat(scan_tokens_yml(allowed))
      violations.concat(scan_scss(allowed))

      if violations.empty?
        Master::Trace::Dmesg.status("rhythm0", "clean, #{allowed.size}-value rhythm, all spacing tokens compliant")
        true
      else
        violations.each do |v|
          Master::Trace::Dmesg.status("rhythm0", "#{v.source}, #{v.name}, #{v.value_px}px is not on the 8px rhythm, allowed #{allowed.to_a.sort.join(", ")}", io: $stderr)
        end
        false
      end
    end

    def load_design_rules = Operator::MasterDesign.blocks

    # The directory holding shared: RAILS/ in a checkout, /home/<app>/ in the
    # copy-tree deploy, where the app and its copy of shared are siblings too.
    def stylesheet_root = File.expand_path("../../RAILS", __dir__)

    def scss_paths
      Dir.glob(File.join(stylesheet_root, "*", "{app,engines/*/app}", "assets", "stylesheets", "**", "*.{scss,css}")).sort
    end

    def to_px(value, unit)
      unit.downcase == "rem" ? (value.to_f * 16).round : value.to_i
    end

    def scan_tokens_yml(allowed)
      data = MasterDesign.tokens
      violations = []
      data.each do |dialect, entries|
        next unless entries.is_a?(Hash)

        entries.each do |key, value|
          next unless key.to_s.match?(SPACE_KEY)
          next unless value.is_a?(String) && value =~ /\A([\d.]+)(rem|px)\z/

          px = to_px(Regexp.last_match(1), Regexp.last_match(2))
          violations << Violation.new("MASTER/data/laws.yml:tokens.#{dialect}", key, px) unless allowed.include?(px)
        end
      end
      violations
    end

    def scan_scss(allowed)
      violations = []
      scss_paths.each do |path|
        next unless File.readable?(path)

        File.readlines(path, encoding: "UTF-8").each do |line|
          next unless (m = line.match(SPACE_CSS_VAR))

          px = to_px(m[2], m[3])
          violations << Violation.new(path.delete_prefix("#{stylesheet_root}/"), "--#{m[1]}", px) unless allowed.include?(px)
        end
      end
      violations
    end
  end
end

exit(Operator::RhythmLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
