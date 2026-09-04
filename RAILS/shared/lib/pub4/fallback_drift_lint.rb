# frozen_string_literal: true

require "set"
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
  #
  # The other half is the token declared nowhere at all. A fallback then always
  # wins, so `var(--card-min-width, 280px)` is 280px wearing a token's clothes,
  # and the indirection reads as configuration nobody can configure; without a
  # fallback the declaration is invalid outright, which is how .tv-feed-title
  # shipped with no font-size at all. Runtime-set names are not undeclared: a
  # helper writing `--nick-hue: 318` into a style attribute, and JS calling
  # setProperty, are both declarations. This reads both, so the check needs no
  # allowlist to maintain.
  module FallbackDriftLint
    FALLBACK = /var\(\s*--([\w-]+)\s*,\s*#([0-9a-fA-F]{3,8})\s*\)/
    LITERAL_DEF = /--([\w-]+)\s*:\s*#([0-9a-fA-F]{3,8})/
    MIXIN_PARAM_DEF = /\$([\w-]+)\s*:\s*#([0-9a-fA-F]{3,8})/
    EXEMPT = %w[accent accent-hover].freeze

    USE = /var\(\s*(--[\w-]+)\s*(,)?/
    DECLARED = /(--[\w-]+)\s*:/
    SET_PROPERTY = /setProperty\(\s*["'](--[\w-]+)["']/
    INTERPOLATION = "#" + "{"
    INTERPOLATION_SEGMENT = /\#\{[^}]*\}/
    INTERPOLATED_DECL = /(--[\w-]*\#\{[^}]*\}[\w-]*)\s*:/
    COMMENT = %r{\A\s*(//|/\*|\*)}

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

      undeclared = undeclared_uses

      if violations.empty? && undeclared.empty?
        puts "fallback_drift_lint: ok (no stale fallbacks, no undeclared tokens)"
        true
      else
        violations.each do |v|
          warn "fallback_drift_lint: #{v.file}:#{v.line} var(#{v.token}, #{v.fallback_hex}) " \
               "matches no real definition of #{v.token}"
        end
        undeclared.each do |v|
          shape = v.fallback_hex ? "the fallback #{v.fallback_hex} always wins" : "no fallback, so the declaration is invalid"
          warn "fallback_drift_lint: #{v.file}:#{v.line} #{v.token} is declared nowhere -- #{shape}"
        end
        false
      end
    end

    # Every name a var() asks for, against every name anything declares: a CSS
    # custom property, a Ruby or ERB helper writing one into a style attribute,
    # or JS calling setProperty. SCSS interpolation (var(--space-#{$step})) is
    # skipped -- the name is composed at compile time and this cannot resolve it.
    def undeclared_uses
      names, families = declared_names
      source_files.flat_map do |path|
        rel = relative(path)
        File.readlines(path, encoding: "UTF-8").each_with_index.flat_map do |line, idx|
        next [] if line.include?(INTERPOLATION) || COMMENT.match?(line)

          line.scan(USE).filter_map do |name, comma|
            next if names.include?(name) || families.any? { |f| f.match?(name) }

            fallback = comma ? fallback_text(line, name) : nil
            Violation.new(rel, idx + 1, name, fallback)
          end
        end
      end
    end

    # var(--a, var(--b)) stops at the first ) if you let it, and the message
    # then quotes half a fallback. Walk the depth instead.
    def fallback_text(line, name)
      rest = line[/var\(\s*#{Regexp.escape(name)}\s*,\s*(.*)/m, 1] or return nil

      depth = 0
      rest.each_char.take_while do |c|
        depth += 1 if c == "("
        depth -= 1 if c == ")"
        depth >= 0
      end.join.strip
    end

    # Two kinds of declaration. A literal `--name:` is a name; an interpolated
    # one is a family. `--vertical-#{$v}-accent:` in _vertical_shell.scss emits
    # seven real properties, and a check that reads only literals accuses every
    # engine that consumes one -- which it did, for --vertical-dating-accent and
    # --vertical-marketplace-accent-hover, both of which exist.
    def declared_names
      names = Set.new
      patterns = []
      source_files.each do |path|
        File.foreach(path, encoding: "UTF-8") do |line|
          line.scan(SET_PROPERTY) { |(n)| names << n }
          line.scan(INTERPOLATED_DECL) { |(stem)| patterns << interpolated_pattern(stem) }
          line.scan(DECLARED) { |(n)| names << n }
        end
      end
      [names, patterns.compact.uniq]
    end

    # `--vertical-#{$v}-accent` becomes /\A--vertical-.+-accent\z/: the stem is
    # fixed, the interpolated segment is whatever the map holds.
    def interpolated_pattern(stem)
      parts = stem.split(INTERPOLATION_SEGMENT, -1)
      return nil if parts.size < 2

      /\A#{parts.map { |p| Regexp.escape(p) }.join(".+")}\z/
    end


    # Wider than scss_files: a declaration can be a helper's string or a
    # setProperty call, and reading only stylesheets would accuse both.
    def source_files
      @source_files ||= scss_files +
                        Dir.glob(File.join(rails_root, "{*,*/engines/*}/app/{helpers,views,javascript}/**/*.{rb,erb,js}")) +
                        Dir.glob(File.join(rails_root, "shared/vendor/javascript/**/*.js"))
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
