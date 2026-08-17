# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/dom_surface_schema"
require_relative "../../support/visual_quality"
require_relative "../../support/exemplar_structure"

module Deploy
  # Tests the gates, not the apps.
  #
  # gates/data/calibration.yml already compares hand-labelled fixtures to gate
  # verdicts — a hand-fed version of this idea, capped at however many fixtures
  # someone was willing to label. This automates the other half: take each
  # *good* fixture, break it the way a real regression would, and assert the
  # suite notices. A mutation that survives is a hole in the gate, and a gate
  # that cannot be broken by the defect it exists to prevent is decoration.
  #
  # Everything here is pure string work over committed fixtures: no browser,
  # no running app, deterministic, fast enough to run on every commit.
  class GateMutationGate
    ROOT = File.expand_path("../../../..", __dir__)
    GATES = File.expand_path("../..", __dir__)
    SURFACES = File.join(GATES, "fixtures", "surfaces")
    EXEMPLARS = File.join(GATES, "fixtures", "exemplars")

    # Each mutation is [id, description, transform]. A transform returns nil
    # when it does not apply to a given fixture (nothing to break), which is
    # reported separately from "applied and survived".
    MUTATIONS = [
      [:drop_h1, "delete the page heading",
       ->(html) { html.match?(/<h1\b/i) ? html.sub(%r{<h1\b[^>]*>.*?</h1>}mi, "") : nil }],

      [:duplicate_h1, "add a competing second h1",
       ->(html) {
         m = html.match(%r{<h1\b[^>]*>.*?</h1>}mi)
         m ? html.sub(m[0], m[0] + "\n<h1>Second competing heading</h1>") : nil
       }],

      [:drop_main, "remove the main landmark",
       ->(html) {
         return nil unless html.match?(/<main\b|id=["']main-content["']/i)

         html.gsub(/<main\b[^>]*>/i, "<div>").gsub(%r{</main>}i, "</div>")
             .gsub(/id=["']main-content["']/i, 'id="content"')
       }],

      [:drop_nav, "remove primary navigation",
       ->(html) {
         html.match?(/<nav\b/i) ? html.gsub(/<nav\b[^>]*>/i, "<div>").gsub(%r{</nav>}i, "</div>") : nil
       }],

      [:auth_wall, "put a signup wall on a guest-open surface",
       ->(html) {
         return nil unless html.match?(/<body[^>]*>/i)

         html.sub(/(<body[^>]*>)/i) { "#{Regexp.last_match(1)}\n<div class=\"gate\">Sign in to continue</div>" }
       }],

      [:strip_alt, "drop image alt text",
       ->(html) { html.match?(/<img\b[^>]*\balt=/i) ? html.gsub(/\s+alt=(["']).*?\1/i, "") : nil }],

      [:mute_buttons, "empty every button's accessible name",
       ->(html) {
         return nil unless html.match?(/<button\b/i)

         html.gsub(%r{(<button\b[^>]*>).*?(</button>)}mi) { "#{Regexp.last_match(1)}#{Regexp.last_match(2)}" }
             .gsub(/\s+aria-label=(["']).*?\1/i, "")
       }],

      [:cta_flood, "multiply primary calls to action past the Hick budget",
       ->(html) {
         return nil unless html.match?(/<body[^>]*>/i)

         extra = Array.new(12) { |i| "<button class=\"btn-primary\" type=\"submit\">Act #{i}</button>" }.join("\n")
         html.sub(/(<body[^>]*>)/i) { "#{Regexp.last_match(1)}\n#{extra}" }
       }],

      [:gut_content, "strip the surface down to an empty shell",
       ->(html) {
         body = html[%r{<body[^>]*>(.*?)</body>}mi, 1]
         return nil if body.nil? || body.length < 400

         html.sub(%r{(<body[^>]*>).*?(</body>)}mi) { "#{Regexp.last_match(1)}<div></div>#{Regexp.last_match(2)}" }
       }],
    ].freeze

    def self.run = new.run

    def run
      @result = GateResult.new
      fixtures = Dir.glob(File.join(SURFACES, "good_*.html")).sort
      if fixtures.empty?
        @result.fail("gate_mutation: no good_* fixtures in #{SURFACES.sub(ROOT + '/', '')}")
        return @result
      end

      @schema = DomSurfaceSchema.new
      @quality = VisualQuality.new
      known = DomSurfaceSchema.load_all.keys

      applied = 0
      survived = []
      inapplicable = 0

      fixtures.each do |path|
        id = File.basename(path).sub(/\Agood_/, "").sub(/\.html\z/, "")
        unless known.include?(id)
          @result.warn("gate_mutation: #{File.basename(path)} has no matching surface schema #{id.inspect} — skipped")
          next
        end

        html = File.read(path)
        baseline = verdict(html, id)
        if baseline[:hard].positive?
          @result.fail(
            "gate_mutation: baseline fixture good_#{id}.html already produces #{baseline[:hard]} hard finding(s) — " \
            "a 'good' fixture the gates reject makes every mutation result meaningless"
          )
          next
        end

        MUTATIONS.each do |mutation_id, description, transform|
          mutant = begin
            transform.call(html.dup)
          rescue StandardError => e
            @result.warn("gate_mutation: #{id}/#{mutation_id} transform raised #{e.class}")
            nil
          end
          if mutant.nil? || mutant == html
            inapplicable += 1
            next
          end

          applied += 1
          after = verdict(mutant, id)
          next if caught?(baseline, after)

          survived << { id: id, mutation: mutation_id, description: description, after: after }
        end
      end

      report(applied, inapplicable, survived)
      @result
    end

    private

    # A mutation is caught if it produces a new hard schema finding, or drops
    # the quality score below its target when the original cleared it.
    def caught?(baseline, after)
      return true if after[:hard] > baseline[:hard]
      return true if baseline[:quality_pass] && !after[:quality_pass]
      return true if after[:soft] > baseline[:soft] && after[:score] < baseline[:score]

      false
    end

    def verdict(html, schema_id)
      findings = @schema.check(html, schema_id)
      quality = @quality.score(html, surface: surface_kind(schema_id))
      {
        hard: findings.count { |f| f.severity == :hard },
        soft: findings.count { |f| f.severity == :soft },
        score: quality.score,
        quality_pass: quality.pass?,
      }
    rescue ArgumentError => e
      { hard: 0, soft: 0, score: 0, quality_pass: true, error: e.message }
    end

    def surface_kind(schema_id)
      case schema_id
      when /marketplace/ then :marketplace
      when /live/ then :live
      when /dating/ then :dating
      else :generic
      end
    end

    def report(applied, inapplicable, survived)
      if applied.zero?
        @result.fail("gate_mutation: no mutation applied to any fixture — the catalogue does not match the corpus")
        return
      end

      caught = applied - survived.size
      rate = (caught.to_f / applied * 100).round
      @result.warn(
        "gate_mutation: #{caught}/#{applied} mutations caught (#{rate}%), #{inapplicable} inapplicable"
      )

      survived.group_by { |row| row[:mutation] }.sort_by { |_m, rows| -rows.size }.each do |mutation, rows|
        surfaces = rows.map { |r| r[:id] }.sort.join(", ")
        @result.fail(
          "gate_mutation: #{mutation} survives on #{surfaces} — the suite does not detect " \
          "\"#{rows.first[:description]}\" on #{rows.size == 1 ? 'this surface' : "#{rows.size} surfaces"}",
          severity: :soft
        )
      end
    end
  end
end
