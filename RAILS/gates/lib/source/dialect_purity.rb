# frozen_string_literal: true

require "yaml"
require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # Dialect purity: social / luxury / CRT / face stay separate; vertical accents single map.
  class DialectPurityGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    TOKENS = File.join(RAILS, "shared", "design_tokens.yml")
    WIRING = File.join(RAILS, "shared", "WIRING_NOTES.md")

    def self.run
      new.run
    end

    def run
      @result = GateResult.new
      check_tokens
      check_wiring_notes
      check_vertical_accents
      check_no_twitter_blue
      check_dialect_roots
      @result
    end

    private

    def check_tokens
      unless File.file?(TOKENS)
        @result.fail("dialect_purity: missing design_tokens.yml")
        return
      end
      data = YAML.safe_load_file(TOKENS)
      %w[social luxury openbsd_wscons face_root vertical_accents].each do |key|
        @result.fail("dialect_purity: design_tokens missing #{key}") unless data.key?(key)
      end
      accents = data["vertical_accents"] || {}
      %w[marketplace dating].each do |v|
        @result.fail("dialect_purity: vertical_accents.#{v} missing") unless accents[v].is_a?(Hash) && accents[v]["accent"]
      end
    end

    def check_wiring_notes
      return @result.fail("dialect_purity: missing WIRING_NOTES.md") unless File.file?(WIRING)

      notes = File.read(WIRING)
      @result.fail("dialect_purity: WIRING_NOTES lost dialect table") unless notes.match?(/social|luxury|openbsd_wscons|face_root/i)
      @result.fail("dialect_purity: WIRING_NOTES lost Flat rule") unless notes.match?(/Flat rule|box-shadow/i)
      @result.fail("dialect_purity: WIRING_NOTES lost vertical accents rule") unless notes.match?(/vertical_accents|_vertical_shell/i)
    end

    def check_vertical_accents
      shell = File.join(RAILS, "brgen/app/assets/stylesheets/_vertical_shell.scss")
      return @result.fail("dialect_purity: missing _vertical_shell.scss") unless File.file?(shell)

      shell_body = File.read(shell)
      @result.fail("dialect_purity: _vertical_shell missing $vertical-accents map") unless shell_body.include?("$vertical-accents")

      # The verticals moved to engines/ and their sheets went with them: the host
      # keeps _vertical_shell and messenger, the other twelve _vertical_*.scss
      # live under engines/<name>/app/assets/stylesheets. Globbing the host alone
      # left this gate reading two files and calling it the dialect.
      vertical_sheets = Dir.glob(File.join(RAILS, "brgen/app/assets/stylesheets/_vertical_*.scss")) +
                        Dir.glob(File.join(RAILS, "brgen/engines/*/app/assets/stylesheets/_vertical_*.scss"))
      vertical_sheets.each do |path|
        next if path.end_with?("_vertical_shell.scss")

        body = File.read(path)
        if body.match?(/--accent\s*:/)
          @result.fail("dialect_purity: #{File.basename(path)} re-sets --accent (shell only)")
        end
      end
    end

    def check_no_twitter_blue
      sheets = Dir.glob(File.join(RAILS, "{brgen,amber,bsdports,shared}/app/assets/stylesheets/**/*.{scss,css}")) +
               Dir.glob(File.join(RAILS, "brgen/engines/*/app/assets/stylesheets/**/*.{scss,css}"))
      sheets.each do |path|
        next if path.include?("/builds/")
        body = File.read(path)
        if body.match?(/#1d9bf0|#1DA1F2/i)
          @result.fail("dialect_purity: twitter blue in #{path.sub(RAILS + '/', '')}")
        end
      end
    end

    def check_dialect_roots
      # brgen uses brgen_old / social; amber luxury; bsdports openbsd greens
      brgen_root = File.join(RAILS, "brgen/app/assets/stylesheets/_root.scss")
      if File.file?(brgen_root)
        body = File.read(brgen_root)
        @result.fail("dialect_purity: brgen _root missing brgen-old or dialect tokens") unless body.match?(/brgen-old|dialect_tokens|brgen_old/i)
      end
      bsd = File.join(RAILS, "bsdports/app/assets/stylesheets/application.scss")
      if File.file?(bsd)
        body = File.read(bsd)
        @result.fail("dialect_purity: bsdports missing CRT green identity") unless body.include?("#63c363") || body.include?("openbsd")
      end
      amber = File.join(RAILS, "amber/app/assets/stylesheets/_variables.scss")
      amber = File.join(RAILS, "amber/app/assets/stylesheets/application.scss") unless File.file?(amber)
      if File.file?(amber)
        # soft check — luxury or brand present
        body = File.read(amber)
        @result.warn("dialect_purity: amber dialect markers weak") unless body.match?(/luxury|brand|editorial|caprasimo|jsfiddle/i) || File.file?(File.join(RAILS, "amber/app/assets/stylesheets/_jsfiddle_chrome.scss"))
      end
    end
  end
end
