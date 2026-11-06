# frozen_string_literal: true

require "json"

module Deploy
  # axe-core (dequelabs/axe-core, MPL-2.0, vendored unmodified with its licence beside it in
  # vendor/axe-core) run inside the page over the CDP session a check already holds: no node at
  # runtime. Its violations are mapped onto the Laws that own them; a rule no Law owns is
  # reported as law=unmapped rather than dropped.
  module Axe
    SOURCE = File.join(__dir__, "vendor", "axe-core", "axe.min.js")

    # Each Law and the axe rules whose violations it owns.
    LAWS = {
      "IMG_ALT" => %w[image-alt input-image-alt role-img-alt svg-img-alt area-alt object-alt],
      "FORM_LABEL" => %w[label label-title-only select-name form-field-multiple-labels],
      "ARIA_LABELS" => %w[button-name link-name aria-command-name aria-input-field-name aria-toggle-field-name
                          aria-meter-name aria-progressbar-name aria-tooltip-name aria-dialog-name frame-title],
      "ARIA_INTERACTIVE" => %w[aria-allowed-attr aria-allowed-role aria-required-attr aria-required-children
                               aria-required-parent aria-roles aria-valid-attr aria-valid-attr-value
                               aria-hidden-focus aria-prohibited-attr],

      "INTERACTION_SEMANTICS" => %w[nested-interactive scrollable-region-focusable focus-order-semantics
                                    tabindex],
      "HTML_HEADING_HIERARCHY" => %w[heading-order page-has-heading-one empty-heading],
      "CONTRAST_TOKENS" => %w[color-contrast color-contrast-enhanced link-in-text-block],
      "TOUCH_TARGET_MIN" => %w[target-size],
      "MOBILE_ACCESSIBILITY_DEFAULTS" => %w[meta-viewport meta-viewport-large html-has-lang html-lang-valid
                                            landmark-one-main region bypass document-title],
    }.freeze

    RULE_LAW = LAWS.flat_map { |law, rules| rules.map { |rule| [rule, law] } }.to_h.freeze

    RUN_JS = <<~'JS'
      axe.run(document, { resultTypes: ["violations"] }).then((r) => JSON.stringify({
        violations: r.violations.map((v) => ({ id: v.id, impact: v.impact, nodes: v.nodes.length,
                                               target: (v.nodes[0] && v.nodes[0].target.join(" ")) || "" })),
        incomplete: r.incomplete.length
      }))
    JS

    module_function

    def source = (@source ||= File.read(SOURCE))

    # { "violations" => [{ "id", "impact", "nodes", "target" }], "incomplete" => n } for the page.
    def run(cdp)
      cdp.evaluate(source) unless cdp.evaluate("typeof window.axe === 'object'")
      JSON.parse(cdp.evaluate(RUN_JS, await_promise: true).to_s)
    end

    def law(rule) = RULE_LAW.fetch(rule, "unmapped")

    def findings(label, report)
      Array(report["violations"]).map do |row|
        "accessibility_axe: #{label} #{row["id"]} x#{row["nodes"]} (#{row["impact"]}) - #{row["target"]} " \
          "law=#{law(row["id"])}"
      end
    end
  end
end
