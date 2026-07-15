#!/usr/bin/env ruby
# frozen_string_literal: true

# One self-contained HTML per idea in BPLAN/ root. HTU = css only (htu/htu.css).
require "fileutils"
require_relative "funding_helpers"
require_relative "lib/bplan/constants"
require_relative "lib/bplan/html"
require_relative "lib/bplan/validate"

ROOT = File.expand_path(__dir__)
FUNDING = FundingHelpers.load_funding(ROOT)

def plan_description(slug, title)
  meta = Bplan::Constants::PLAN_META[slug]
  plain = meta ? meta.gsub("<br>", " — ") : title
  "#{title}. #{plain}. Bergen, #{Bplan::Constants::DATE}."
end

def venture_extra(slug)
  case slug
  when "master"
    <<~HTML
      <h2>4. Innovasjon</h2>
      <p>Styrt evolusjon, ikke ukontrollert autonomi. Konstitusjonelle prinsipper fra Clean Code, SOLID og Pragmatic Programmer. Kostnadskontroll, kretssikrere, CRDT-konvergens.</p>
    HTML
  when "pub_healthcare"
    <<~HTML
      <h2>4. Problem og løsning</h2>
      <p>Fragmentert samhandling og administrativ byrde. Norske, sikre webapplikasjoner for koordinering og informasjon — pilot i Vestland, uten å erstatte klinisk skjønn.</p>
    HTML
  when "brgen"
    <<~HTML
      <h2>4. Samfunnsnytte</h2>
      <p>Trygg identitet (Vipps/Google), moderering, tillitssignaler og velferdsteknologi for det sivile samfunn i Bergen. Reell deploybar Rails 8-app.</p>
    HTML
  when "syre"
    <<~HTML
      <div class="image-grid">
        <figure><img src="assets/ivaar_fkyeah1.png" alt="SYRE modell 1" loading="lazy"></figure>
        <figure><img src="assets/ivaar_fkyeah2.png" alt="SYRE modell 2" loading="lazy"></figure>
        <figure><img src="assets/ivaar_fkyeah3.png" alt="SYRE modell 3" loading="lazy"></figure>
      </div>
      <h2>4. Produksjon</h2>
      <p>Lokal prototyping først — 5–10 par, materialtest, deretter skalerbar produksjon. Ikke massefabrikk på dag én.</p>
    HTML
  when "bolig_bergen"
    FundingHelpers.bolig_channels_block(FUNDING) +
      FundingHelpers.bolig_portal_checklist_block(FUNDING) +
      FundingHelpers.bolig_budget_block(FUNDING) +
      FundingHelpers.claims_block("bolig_bergen", FUNDING)
  when "personal"
    FundingHelpers.personal_use_of_funds_block(FUNDING) +
      FundingHelpers.claims_block("personal", FUNDING)
  else
    ""
  end
end

def build_plan_body(slug, _venture)
  if slug == "bolig_bergen"
    return FundingHelpers.summary_block(slug, FUNDING) + venture_extra(slug)
  end

  if slug == "personal"
    return FundingHelpers.summary_block(slug, FUNDING) + venture_extra(slug)
  end

  [
    FundingHelpers.summary_block(slug, FUNDING),
    FundingHelpers.executive_summary_block(slug, FUNDING),
    FundingHelpers.wholesome_block(slug, FUNDING),
    venture_extra(slug),
    FundingHelpers.budget_table(slug, FUNDING),
    FundingHelpers.funders_table(FUNDING, venture: slug),
    FundingHelpers.claims_block(slug, FUNDING),
  ].join("\n")
end

PLAN_DEFS = Bplan::Constants::PLAN_ORDER.map do |slug|
  v = FUNDING["ventures"][slug]
  raise "Missing venture #{slug} in funding.yml" unless v

  {
    slug: slug,
    title: v["title"],
    meta: Bplan::Constants::PLAN_META[slug] || "#{v['track']} · Bergen",
    body: build_plan_body(slug, v),
  }
end

PLAN_DEFS.each do |p|
  path = File.join(ROOT, "#{p[:slug]}.html")
  File.write(
    path,
    Bplan::Html.plan_html(
      title: p[:title],
      description: plan_description(p[:slug], p[:title]),
      meta: p[:meta],
      body: p[:body],
      slug: p[:slug],
      order: Bplan::Constants::PLAN_ORDER,
    ),
  )
  puts "wrote #{p[:slug]}.html"
end

File.write(
  File.join(ROOT, "index.html"),
  Bplan::Html.plans_index_html(plan_defs: PLAN_DEFS, funding: FUNDING, helpers: FundingHelpers),
)
puts "wrote index.html (#{PLAN_DEFS.size} ideas)"

sitemap_urls = [Bplan::Constants::BASE_URL + "/"] +
               PLAN_DEFS.map { |p| "#{Bplan::Constants::BASE_URL}/#{p[:slug]}.html" } +
               ["#{Bplan::Constants::BASE_URL}/legats/index.html"]
File.write(File.join(ROOT, "sitemap.xml"), Bplan::Html.sitemap_xml(sitemap_urls))
puts "wrote sitemap.xml"

File.write(File.join(ROOT, "robots.txt"), Bplan::Html.robots_txt)
puts "wrote robots.txt"

Bplan::Validate.validate_all!(ROOT, funding: FUNDING, plan_defs: PLAN_DEFS, helpers: FundingHelpers)
Bplan::Validate.write_build_id!(ROOT)
puts "validated venture budgets (convergence v#{FUNDING.dig('portfolio', 'convergence_version') || 1})"