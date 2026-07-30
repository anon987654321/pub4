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
    assert Deploy::DomSurfaceSchema.load_all.key?("live_feed")
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

  def test_good_live_fixture_passes
    html = File.read(File.join(FIXTURES, "good_live_feed.html"))
    hard = @schema.check(html, "live_feed").select { |f| f.severity == :hard }
    assert_empty hard.map(&:message)
  end

  def test_bad_live_fixture_catches_auth_wall
    html = File.read(File.join(FIXTURES, "bad_live_feed.html"))
    findings = @schema.check(html, "live_feed")
    assert findings.any?, "gate must not be blind to bad live fixture"
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

  def test_mutation_inject_auth_wall_is_caught
    good = File.read(File.join(FIXTURES, "good_live_feed.html"))
    mutated = good.sub("</main>", "<p>Sign in to continue</p></main>")
    findings = @schema.check(mutated, "live_feed")
    assert findings.any? { |f| f.message.match?(/forbidden|Sign in/i) }, findings.map(&:message).inspect
  end

  def test_mutation_strip_nav_is_caught
    good = File.read(File.join(FIXTURES, "good_marketplace_listings.html"))
    mutated = good.gsub(/id="navBar"/, 'id="notBar"')
    findings = @schema.check(mutated, "marketplace_listings")
    assert findings.any? { |f| f.message.include?("nav_bar") }, findings.map(&:message).inspect
  end
end
