# frozen_string_literal: true

require "test_helper"

class CatalogTest < ActiveSupport::TestCase
  test "loads plans from funding.yml" do
    plans = Bplan::Catalog.plans
    assert plans.size >= 15
    assert_equal "master", plans.first[:slug]
  end

  test "loads legats from manifest" do
    assert Bplan::Catalog.legats.size >= 90
  end

  test "extracts plan html with content paths" do
    body = Bplan::Catalog.plan_html("syre")
    assert_includes body, "Budsjett"
    assert_includes body, "/content/assets/"
  end

  test "portfolio summary converges on funding.yml" do
    html = Bplan::Catalog.portfolio_summary_html
    assert_includes html, "Portefølje"
    assert_includes html, "Anti-dobbelsøk"
    assert_includes html, "250000–500000"
  end

  test "deadline calendar loads from funding.yml" do
    assert Bplan::Catalog.deadlines.size >= 5
    html = Bplan::Catalog.deadline_calendar_html
    assert_includes html, "Gunvor Mindes"
    assert_includes html, "2026-09-20"
  end

  test "plan html includes vision from funding.yml" do
    body = Bplan::Catalog.plan_html("master")
    assert_includes body, "Visjon:"
    assert_includes body, "konstitusjonelle rammer"
  end

  test "bolig portal batch pending helper" do
    assert_includes [true, false], Bplan::Catalog.bolig_portal_sept_pending?
  end

  test "venture budgets use per-idea breakdown lines" do
    body = Bplan::Catalog.plan_html("pub_healthcare")
    assert_includes body, "DPIA"
    assert_includes body, "650 000"

    syre = Bplan::Catalog.plan_html("syre")
    assert_includes syre, "3D-print"
    assert_includes syre, "550 000"
  end

  test "legats_filtered by track" do
    bolig = Bplan::Catalog.legats_filtered(track: "bolig")
    assert bolig.all? { |entry| entry["track"] == "bolig" }
    assert bolig.size.positive?
  end

  test "legats_sendable excludes drafts and innovasjon norge when blocked" do
    sendable = Bplan::Catalog.legats_sendable
    assert sendable.none? { |entry| entry["draft"] }
    assert sendable.none? { |entry| entry["id"].include?("innovasjon_norge") }
  end

  test "legats_by_deadline sorts dated entries first" do
    sorted = Bplan::Catalog.legats_by_deadline
    keys = sorted.map { |entry| Bplan::Catalog.legat_deadline_sort_key(entry) }
    assert keys == keys.sort
  end

  test "portfolio_json exposes convergence version" do
    json = Bplan::Catalog.portfolio_json
    assert json[:convergence_version].present?
    assert json[:anti_double_dip].is_a?(Array)
  end

  test "document_body strips script tags" do
    dir = Bplan::Catalog::BPLAN_ROOT
    path = dir.join("_script_probe.html")
    path.write(<<~HTML)
      <div class="content"><p>OK</p><script>alert(1)</script></div>
      <footer></footer>
    HTML
    body = Bplan::Catalog.document_body("_script_probe.html")
    assert_includes body, "OK"
    assert_not_includes body, "script"
    path.delete
    Bplan::Catalog.reload!
  end
end