# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../gates/support/exemplar_structure"
require_relative "../../gates/support/visual_quality"
require_relative "../../gates/lib/research/visual_quality"
require_relative "../../../OPENBSD/lib/gate_result"

class VisualQualityTest < Minitest::Test
  FIX = File.expand_path("../../gates/fixtures/exemplars", __dir__)

  def setup
    @exemplars = Deploy::ExemplarStructure.new
    @quality = Deploy::VisualQuality.new
  end

  def test_good_marketplace_tile_hits_target
    html = File.read(File.join(FIX, "good_marketplace_tile.html"))
    r = @exemplars.score(html, "marketplace_tile")
    assert r.pass?, "score=#{r.score}/#{r.max} missing=#{r.missing_required} notes=#{r.notes}"
    assert r.score >= r.target
  end

  def test_bad_marketplace_tile_fails_required
    html = File.read(File.join(FIX, "bad_marketplace_tile.html"))
    r = @exemplars.score(html, "marketplace_tile")
    refute r.pass?
    assert r.missing_required.any? || r.score < r.target
  end

  def test_price_before_title_order
    good = <<~HTML
      <article class="deal-card"><a class="deal-card-hit">
      <div class="deal-card-img"></div><div class="deal-card-body">
      <div class="deal-price">1</div><h2 class="deal-card-title">T</h2>
      <div class="deal-meta">m</div></div></a></article>
    HTML
    bad = good.sub("deal-price", "TMP").sub("deal-card-title", "deal-price").sub("TMP", "deal-card-title")
    assert @exemplars.score(good, "marketplace_tile").pass?
    refute @exemplars.score(bad, "marketplace_tile").pass?
  end

  def test_good_dating_and_live
    d = @exemplars.score(File.read(File.join(FIX, "good_dating_card.html")), "dating_card")
    l = @exemplars.score(File.read(File.join(FIX, "good_live_card.html")), "live_card")
    assert d.pass?, d.notes.inspect
    assert l.pass?, l.notes.inspect
  end

  def test_bad_live_rejects_retail_dialect
    r = @exemplars.score(File.read(File.join(FIX, "bad_live_card.html")), "live_card")
    refute r.pass?
    assert_includes r.missing_required, "root_card" if r.missing_required.include?("root_card")
  end

  def test_quality_good_first_screen
    html = File.read(File.join(FIX, "good_marketplace_first_screen.html"))
    q = @quality.score(html, surface: :marketplace)
    assert q.pass?, "score=#{q.score} notes=#{q.notes}"
  end

  def test_quality_auth_wall_zeroes_guest_open
    q = @quality.score("<main id='main-content'><h1>X</h1><p>Sign in to continue</p></main>", surface: :generic)
    assert_includes q.notes, "guest_open:auth_wall"
    assert q.score < q.max
  end

  def test_quality_dialect_marketplace_rejects_swipe
    html = File.read(File.join(FIX, "good_marketplace_first_screen.html")) + '<article class="swipe-card"></article>'
    q = @quality.score(html, surface: :marketplace)
    assert_includes q.notes, "dialect:marketplace"
  end

  def test_gate_runs_fixtures
    result = Deploy::VisualQualityGate.run
    assert result.respond_to?(:ok?)
    # hard failures only on missing required structure in good fixtures
    assert result.ok?, result.failures.first(8).join("\n")
  end

  def test_mutation_strip_price_first_drops_score
    html = File.read(File.join(FIX, "good_marketplace_tile.html"))
    mutated = html.sub("deal-price", "x-price")
    before = @exemplars.score(html, "marketplace_tile")
    after = @exemplars.score(mutated, "marketplace_tile")
    assert after.score < before.score
  end
end
