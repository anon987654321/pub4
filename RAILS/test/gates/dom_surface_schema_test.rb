# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../gates/support/dom_surface_schema"
require_relative "../../../OPENBSD/lib/gate_result"

class DomSurfaceSchemaTest < Minitest::Test
  FIXTURES = File.expand_path("../../gates/fixtures/surfaces", __dir__)

  def setup
    @schema = Deploy::DomSurfaceSchema.new
  end

  def test_schemas_yml_loads
    assert Deploy::DomSurfaceSchema.load_all.key?("marketplace_listings")
    # live_feed went with /live when 76612fd0b folded it into /nearby/room, and
    # its two fixtures went with it. The schema, the mappings and these tests
    # were the three places that outlived the surface.
  end

  def test_good_marketplace_fixture_passes
    html = File.read(File.join(FIXTURES, "good_marketplace_listings.html"))
    findings = @schema.check(html, "marketplace_listings")
    hard = findings.select { |f| f.severity == :hard }
    assert_empty hard.map(&:message), hard.map(&:message).join("\n")
  end

  def test_bad_marketplace_fixture_fails
    html = File.read(File.join(FIXTURES, "bad_marketplace_listings.html"))
    findings = @schema.check(html, "marketplace_listings")
    assert findings.any? { |f| f.message.include?("missing marker") || f.message.include?("forbidden") },
           "expected structural findings, got #{findings.inspect}"
    assert findings.any? { |f| f.message.include?("Sign in") || f.message.include?("forbidden") }
  end

  def test_order_violation_detected
    # product grid before nav — hard order fail
    html = <<~HTML
      <main id="main-content"><div class="deal-grid deal-card"></div>
      <div id="navBar" class="search marketplace-nav-search"><input name="q"></div>
      <a href="/cart">Cart</a></main>
    HTML
    findings = @schema.check(html, "marketplace_listings")
    assert findings.any? { |f| f.message.include?("order") }, findings.map(&:message).inspect
  end

  def test_apply_to_result_respects_soft_severity
    result = Deploy::GateResult.new
    html = File.read(File.join(FIXTURES, "bad_marketplace_listings.html"))
    @schema.apply_to_result!(result, html, "marketplace_listings")
    refute result.ok?
    assert result.failures.any?
  end

# Was inject_auth_wall against good_live_feed: live_feed was the guest-open
# surface whose schema forbade a sign-in prompt, and it went with /live. The
# test is about the schema not being blind to a mutation, not about that one
# pattern, so it mutates a surface that still exists against a rule that still
# exists — an unlabelled button, which every surviving schema forbids.
def test_mutation_inject_unlabelled_button_is_caught
  good = File.read(File.join(FIXTURES, "good_brgen_home.html"))
  mutated = good.sub("</main>", "<button></button></main>")
  findings = @schema.check(mutated, "brgen_home")

  assert findings.any? { |f| f.message.match?(/forbidden/i) }, findings.map(&:message).inspect
end

  def test_mutation_strip_nav_is_caught
    good = File.read(File.join(FIXTURES, "good_marketplace_listings.html"))
    mutated = good.gsub(/id="navBar"/, 'id="notBar"')
    findings = @schema.check(mutated, "marketplace_listings")
    assert findings.any? { |f| f.message.include?("nav_bar") }, findings.map(&:message).inspect
  end
end
