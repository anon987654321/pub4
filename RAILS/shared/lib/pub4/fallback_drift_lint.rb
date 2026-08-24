# frozen_string_literal: true

require "yaml"

module Pub4
  # Flags var(--token, #hex) fallbacks whose hex literal matches NO real
  # definition of that token anywhere in the token sources. Collects the
  # "known good" set for each token name from three places, since this
  # codebase spreads real definitions across all of them:
  #   1. design_tokens.yml dialect blocks (x_search_bg: "#...", etc.)
  #   2. _dialect_tokens.scss mixin parameter defaults ($accent: #... -> --accent)
  #   3. literal `--token: #hex;` CSS declarations anywhere
  # --accent / --accent-hover are exempt: by design they legitimately
  # take a different value per vertical/app, so "matches no known value"
  # would be noise, not a bug, for those two specifically.
  #
  # Catches the class of bug found 2026-07-21: --danger's fallback was a
  # stale Twitter red (#f4212e) that matched none of its real definitions.
  module FallbackDriftLint
    FALLBACK = /var\(\s*--([\w-]+)\s*,\s*#([0-9a-fA-F]{3,8})\s*\)/
    LITERAL_DEF = /--([\w-]+)\s*:\s*#([0-9a-fA-F]{3,8})/
    MIXIN_PARAM_DEF = /\$([\w-]+)\s*:\s*#([0-9a-fA-F]{3,8})/
    EXEMPT = %w[accent accent-hover].freeze

    Violation = Struct.new(:file, :line, :token, :fallback_hex)

    module_function

    def run
      known = collect_known_values
      violations = []

      scss_files.each do |path|
        File.readlines(path, encoding: "UTF-8").each_with_index do |line, idx|
          line.scan(FALLBACK).each do |token, hex|
            token = token.downcase
            next if EXEMPT.include?(token)

            values = known[token]
            next if values.nil? || values.empty? # no definition found anywhere -- nothing to compare against
            next if values.include?(hex.downcase)

            violations << Violation.new(relative(path), idx + 1, "--#{token}", "##{hex}")
          end
        end
      end

      if violations.empty?
        puts "fallback_drift_lint: ok (no stale var() fallbacks found)"
        true
      else
        violations.each do |v|
          warn "fallback_drift_lint: #{v.file}:#{v.line} var(#{v.token}, #{v.fallback_hex}) " \
               "matches no real definition of #{v.token}"
        end
        false
      end
    end

    def rails_root
      File.expand_path("../../..", __dir__) # RAILS/
    end

    def relative(path)
      path.sub("#{rails_root}/", "")
    end

    # brgen's verticals are mountable engines, so their stylesheets live at
    # brgen/engines/<name>/app/assets/stylesheets — outside the first glob.
    # A stale --text-secondary fallback sat in the playlist engine unseen
    # because of it; the same blind spot cost four other scanners 57 views
    # when the verticals moved.
    def scss_files
      Dir.glob(File.join(rails_root, "*/app/assets/stylesheets/**/*.scss")) +
        Dir.glob(File.join(rails_root, "*/engines/*/app/assets/stylesheets/**/*.scss"))
    end

    def collect_known_values
      known = Hash.new { |h, k| h[k] = [] }
      collect_from_yaml(known)
      collect_from_scss(known)
      known
    end

    def collect_from_yaml(known)
      path = File.join(rails_root, "shared/design_tokens.yml")
      return unless File.readable?(path)

      YAML.safe_load_file(path).each_value do |entries|
        next unless entries.is_a?(Hash)

        entries.each do |key, value|
          if value.is_a?(String) && value =~ /\A#([0-9a-fA-F]{3,8})\z/
            known[key.to_s.tr("_", "-")] << Regexp.last_match(1).downcase
          elsif value.is_a?(Hash) && value["accent"] # vertical_accents-style nested block
            known["accent"] << value["accent"].to_s.delete("#").downcase
            known["accent-hover"] << value["hover"].to_s.delete("#").downcase if value["hover"]
          end
        end
      end
    end

    def collect_from_scss(known)
      scss_files.each do |path|
        File.foreach(path, encoding: "UTF-8") do |line|
          line.scan(LITERAL_DEF).each { |name, hex| known[name.downcase] << hex.downcase }
          line.scan(MIXIN_PARAM_DEF).each { |name, hex| known[name.downcase] << hex.downcase }
        end
      end
    end
  end
end

exit(Pub4::FallbackDriftLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
