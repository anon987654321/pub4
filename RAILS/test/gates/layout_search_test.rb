# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../gates/support/layout_search"
require_relative "../../gates/lib/research/layout_search"
require_relative "../../../OPENBSD/lib/gate_result"

class LayoutSearchTest < Minitest::Test
  def setup
    @search = Deploy::LayoutSearch.new
    @winner_ctx = {
      card: <<~HTML,
        <article class="deal-card">
          <a class="deal-card-hit" href="/x">
            <div class="deal-card-img"></div>
            <div class="deal-card-body">
              <div class="deal-price">10</div>
              <h2 class="deal-card-title">T</h2>
            </div>
          </a>
        </article>
      HTML
      nav: '<div id="navBar">nav</div>',
      search: ".search { border-radius: 30px; }",
    }
  end

  def test_enumerates_full_space
    n = @search.enumerate.size
    # 2^5 axes
    assert_equal 32, n
  end

  def test_winner_is_price_photo_whole_amazon_yep
    win = @search.winner(@winner_ctx)
    assert win
    assert_equal "price_first", win.axes["price_placement"]
    assert_equal "photo_first", win.axes["media_placement"]
    assert_equal "whole_card", win.axes["hit_model"]
    assert_equal "amazon_nav", win.axes["nav_model"]
    assert_equal "yep_search", win.axes["search_model"]
    assert win.hard_ok
  end

  def test_observed_matches_winner_on_ideal_ctx
    report = @search.report(@winner_ctx)
    assert_equal 1, report[:observed_rank]
    assert report[:hard_required_ok]
    assert report[:observed_candidate].score >= report[:target]
  end

  def test_title_first_ranks_worse
    bad = @winner_ctx.merge(
      card: @winner_ctx[:card].sub("deal-price", "TMP").sub("deal-card-title", "deal-price").sub("TMP", "deal-card-title")
    )
    report = @search.report(bad)
    assert report[:observed_rank].nil? || report[:observed_rank] > 1 || !report[:hard_required_ok]
    refute_equal "price_first", report[:observed].axes["price_placement"]
  end

  def test_multi_cta_loses_to_whole_card
    ranking = @search.rank(@winner_ctx)
    whole = ranking.find { |c| c.axes["hit_model"] == "whole_card" && c.axes["price_placement"] == "price_first" }
    multi = ranking.find { |c| c.axes["hit_model"] == "multi_cta" && c.axes["price_placement"] == "price_first" && c.axes["media_placement"] == "photo_first" && c.axes["nav_model"] == "amazon_nav" && c.axes["search_model"] == "yep_search" }
    assert whole && multi
    assert whole.score > multi.score, "whole=#{whole.score} multi=#{multi.score}"
  end

  def test_combo_bonus_tise_natural
    win = @search.winner(@winner_ctx)
    assert win.breakdown[:combo].to_i >= 12, win.breakdown.inspect
  end

  def test_gate_passes_on_repo_marketplace
    result = Deploy::LayoutSearchGate.run
    assert result.ok?, result.failures.join("\n")
  end

  def test_gate_fails_on_title_first_mutation
    title_first = {
      card: <<~HTML,
        <article class="deal-card">
          <a class="deal-card-hit">
            <div class="deal-card-img"></div>
            <div class="deal-card-body">
              <h2 class="deal-card-title">Title first</h2>
              <div class="deal-price">10</div>
            </div>
          </a>
        </article>
      HTML
      nav: @winner_ctx[:nav],
      search: @winner_ctx[:search],
    }
    report = @search.report(title_first)
    assert_equal "title_first", report[:observed].axes["price_placement"]
    refute report[:hard_required_ok], "title-first must fail hard floor"
  end

  def test_legal_set_only_hard_floor_variants
    legal = @search.rank(@winner_ctx)
    assert legal.all?(&:hard_ok)
    assert legal.all? { |c| c.axes["price_placement"] == "price_first" }
    assert_equal 2, legal.size # whole_card vs multi_cta only free axis under hard floor
  end
end
