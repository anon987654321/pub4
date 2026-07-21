# frozen_string_literal: true

module Pub4
  # Flags var(--token, #hex) fallbacks whose hex literal doesn't match ANY
  # real definition of that token anywhere in the token-source files. A
  # token like --x-accent legitimately has many valid values (one per
  # vertical/app), so this collects every definition site into an allowed
  # set per token name rather than assuming a single canonical value --
  # only a fallback matching NONE of them is flagged. Catches the class of
  # bug found 2026-07-21: --x-danger fallback was a stale Twitter red that
  # matched no real definition anywhere.
  module FallbackDriftLint
    FALLBACK = /var\(\s*--([\w-]+)\s*,\s*#([0-9a-fA-F]{3,8})\s*\)/
    DEFINITION = /--([\w-]+)\s*:\s*#([0-9a-fA-F]{3,8})/

    Violation = Struct.new(:file, :line, :token, :fallback_hex)

    module_function

    def run
      canonical = collect_definitions(source_root)
      violations = []

      scss_files(source_root).each do |path|
        File.readlines(path).each_with_index do |line, idx|
          line.scan(FALLBACK).each do |token, hex|
            known = canonical[token.downcase]
            next if known.nil? || known.empty? # no definition found anywhere -- nothing to compare against
            next if known.include?(hex.downcase)

            violations << Violation.new(relative(path), idx + 1, "--#{token}", "##{hex}")
          end
        end
      end

      if violations.empty?
        puts "fallback_drift_lint: ok (no stale var() fallbacks found)"
        true
      else
        violations.each do |v|
          warn "fallback_drift_lint: #{v.file}:#{v.line} var(#{v.token}, #{v.fallback_hex}) matches no real definition of #{v.token}"
        end
        false
      end
    end

    def source_root
      File.expand_path("../../..", __dir__) # RAILS/
    end

    def relative(path)
      path.sub("#{source_root}/", "")
    end

    def scss_files(root)
      Dir.glob(File.join(root, "*/app/assets/stylesheets/**/*.scss")) +
        Dir.glob(File.join(root, "shared/app/assets/stylesheets/**/*.scss"))
    end

    # Every --token: #hex declaration anywhere in the tree is a "real"
    # definition -- including per-vertical/per-app overrides, which is the
    # point: --x-accent has dozens of legitimate values, one per vertical.
    def collect_definitions(root)
      defs = Hash.new { |h, k| h[k] = [] }
      scss_files(root).each do |path|
        File.foreach(path) do |line|
          line.scan(DEFINITION).each do |token, hex|
            defs[token.downcase] << hex.downcase
          end
        end
      end
      defs
    end
  end
end

exit(Pub4::FallbackDriftLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
