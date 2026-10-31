# frozen_string_literal: true

require_relative "../../../tools/master_design"
require_relative "../../support/check_result"
require_relative "../../../tools/scss"

module Deploy
  # Dialect purity: social / luxury / CRT / face stay separate; vertical accents single map.
  class DialectPurityCheck
    ROOT = File.expand_path("../../../..", __dir__)

    # Twitter's brand blue. The X.com mirror the operator recorded on
    # 2026-10-28 declares it as brgen's palette tokens; a declaration of the
    # token is the palette, a use-site carrying the literal is drift.
    TWITTER_BLUE = /#1d9bf0|#1DA1F2/i
    TOKEN_DECLARATION_SPAN = /--[\w-]+\s*:[^;}]*/

    def self.run(root: ROOT)
      new(root:).run
    end

    def initialize(root: ROOT)
      @rails = File.join(root, "RAILS")
      @master_rules = File.join(root, "MASTER", "data", "tokens.yml")
      # The design system's written rules live in __shared/README.md; what this
      # checks is that the three it names are still written down there.
      @design_doc = File.join(@rails, "__shared", "README.md")
    end

    def run
      @result = CheckResult.new
      check_tokens
      check_design_doc
      check_vertical_accents
      check_no_twitter_blue
      check_dialect_roots
      @result
    end

    private

    def check_tokens
      data = Operator::MasterDesign.tokens(@master_rules)
      if data.empty?
        @result.fail("dialect_purity: missing MASTER/data/tokens.yml")
        return
      end
      @result.checked!(7)

      %w[social luxury openbsd_wscons face_root vertical_accents].each do |key|
        @result.fail("dialect_purity: MASTER tokens missing #{key}") unless data.key?(key)
      end
      accents = data["vertical_accents"] || {}
      %w[marketplace dating].each do |v|
        @result.fail("dialect_purity: MASTER tokens vertical_accents.#{v} missing") unless accents[v].is_a?(Hash) && accents[v]["accent"]
      end
    end

    def check_design_doc
      return @result.fail("dialect_purity: missing __shared/README.md, the design system's rules") unless File.file?(@design_doc)

      notes = File.read(@design_doc)
      @result.checked!(3)
      @result.fail("dialect_purity: __shared/README.md lost the dialect table") unless notes.match?(/social|luxury|openbsd_wscons|face_root/i)
      @result.fail("dialect_purity: __shared/README.md lost the Flat rule") unless notes.match?(/Flat rule|box-shadow|interface is flat/i)
      @result.fail("dialect_purity: __shared/README.md lost the vertical accents rule") unless notes.match?(/vertical_accents|_vertical_shell|per-vertical accent/i)
    end

    # brgen sets --accent in one place: the map over $vertical-accents, which
    # gives each vertical its own. A vertical that re-sets the accent for itself
    # takes the colour out of the map and puts it where nothing else reads it.
    #
    # Every rule in brgen's stylesheets that declares --accent has to sit inside
    # that map's @each. The rule, not the file, is the unit: brgen compiles from
    # one application.scss, and a vertical's styles are rules in it. Engine
    # stylesheet directories are read too, so an engine that grows a sheet of
    # its own again is still held to the map.
    def check_vertical_accents
      sheets = brgen_stylesheets

      return @result.fail("dialect_purity: brgen has no application.scss") if sheets.empty?

      sources = sheets.to_h { |path| [path, File.read(path)] }
      @result.checked!
      unless sources.values.any? { |body| body.include?("$vertical-accents") }
        @result.fail("dialect_purity: brgen's stylesheet carries no $vertical-accents map")
      end

      sources.each do |path, body|
        @result.checked!
        Operator::ScssRules.rules(body).each do |rule|
          next unless rule.body.match?(/(?<![\w-])--accent\s*:/)
          next if rule.parents.any? { |parent| parent.match?(/\A@each\b.*\$vertical-accents\b/) }
          # The root dialect's own :root declaration is the palette the mirror
          # recorded on 2026-10-28 (--accent: #1d9bf0 with black ink); the map
          # governs the verticals, not the host's root.
          next if rule.selector == ":root" && rule.parents.empty?

          @result.fail("dialect_purity: #{path.sub(@rails + '/', '')}:#{rule.line} #{rule.selector} " \
                       "re-sets --accent (the accent map only)")
        end
      end
    end

    def brgen_stylesheets
      Dir.glob(File.join(@rails, "brgen/app/assets/stylesheets/**/*.scss")) +
        Dir.glob(File.join(@rails, "brgen_*/{,*/,engines/*/}app/assets/stylesheets/**/*.scss"))
    end

    # The dialect must not paint twitter blue. The one exemption is the token
    # declaration itself: the X.com mirror the operator recorded on 2026-10-28
    # defines --accent, --nav-rule and --nav-badge-fill as #1d9bf0 on :root, and
    # a palette declaration is the line every use-site is supposed to cite. A
    # use-site carrying the literal still fails.
    def check_no_twitter_blue
      sheets = Dir.glob(File.join(@rails, "{brgen,amber,bsdports,__shared}/app/assets/stylesheets/**/*.{scss,css}")) +
               Dir.glob(File.join(@rails, "brgen_*/{,*/,engines/*/}app/assets/stylesheets/**/*.{scss,css}"))
      sheets.each do |path|
        next if path.include?("/builds/")

        @result.checked!
        body = Operator::ScssRules.without_comments(File.read(path))
        if body.lines.any? { |line| line.gsub(TOKEN_DECLARATION_SPAN, "").match?(TWITTER_BLUE) }
          @result.fail("dialect_purity: twitter blue in #{path.sub(@rails + '/', '')}")
        end
      end
    end

    # Each app's dialect is what its own stylesheet puts on :root. brgen wears
    # brgen_old, and the proof is a :root rule that includes those tokens rather
    # than the name appearing somewhere in the file.
    def check_dialect_roots
      brgen = app_stylesheet("brgen")

      if brgen
        roots = Operator::ScssRules.rules(File.read(brgen)).select { |rule| rule.selector.start_with?(":root") }
        @result.fail("dialect_purity: brgen's :root does not include the brgen-old tokens") unless roots.any? { |rule| rule.body.match?(/brgen-old/) }
      else
        @result.fail("dialect_purity: brgen has no application.scss")
      end

      # bsdports wears the wscons dialect's square corners on a light ground, so
      # the proof is a plain :root rule zeroing the card and pill radii.
      bsd = app_feature_stylesheet("bsdports", "_bsdports_tokens.scss")
      if bsd
        roots = Operator::ScssRules.rules(File.read(bsd)).select { |rule| rule.selector == ":root" && rule.parents.empty? }
        square = roots.any? { |rule| rule.body.match?(/--radius-card:\s*0\s*;/) && rule.body.match?(/--radius-pill:\s*0\s*;/) }
        @result.fail("dialect_purity: bsdports' :root does not zero the wscons radii") unless square
      end

      amber = app_stylesheet("amber")
      return unless amber

      # soft check — luxury or brand present
      @result.warn("dialect_purity: amber dialect markers weak") unless File.read(amber).match?(/luxury|brand|editorial|caprasimo|jsfiddle/i)
    end

    def app_stylesheet(app)
      path = File.join(@rails, app, "app/assets/stylesheets/application.scss")
      File.file?(path) ? path : nil
    end

    def app_feature_stylesheet(app, name)
      path = File.join(@rails, app, "app/assets/stylesheets", name)
      File.file?(path) ? path : nil
    end
  end
end
