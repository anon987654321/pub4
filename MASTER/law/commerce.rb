# frozen_string_literal: true

# Commerce ownership and evidence stay constitutional. The two product systems
# exchange a small protocol, not each other's domain objects.
Law.define(:COMMERCE_AMBER_DOES_NOT_OWN_BRGEN) do
  source "pub4 commerce boundary — BRGEN owns listings/orders; Amber owns wardrobe intelligence"
  severity :error
  mode :violation
  path "RAILS/amber/"
  detect { |line| line.match?(/\bMarketplace::(?:Listing|Order|Store)\b/) }
  fix "Consume the public Shared::Commerce/BRGEN catalog contract through BrgenCommerce; do not load BRGEN models."
  bad "Marketplace::Order.where(payment_status: "paid")"
  good "BrgenCommerce.search(item: item, limit: 6)"
end

Law.define(:COMMERCE_BRGEN_DOES_NOT_OWN_AMBER) do
  source "pub4 commerce boundary — Amber owns wardrobe intelligence; BRGEN owns transactions"
  severity :error
  mode :violation
  path "RAILS/brgen/engines/marketplace/"
  detect { |line| line.match?(/\b(?:TasteRanker|WardrobeGap|ShopTheLook|WardrobeItem)\b/) }
  fix "Keep wardrobe ranking and wardrobe records in Amber; expose only commerce references and catalog facts across the boundary."
  bad "TasteRanker.new(Current.user).rank(listings)"
  good "Marketplace::SearchRanker.new(listings, query: query, viewer: Current.user).relation"
end

Law.define(:COMMERCE_EXTERNAL_SOURCES_STAY_EXPLAINABLE) do
  source "pub4 commerce protocol — external inventory must carry source and provenance"
  severity :error
  mode :violation
  path "RAILS/amber/app/services/"
  detect { |line| line.match?(/Suggestion\.new\([^\n]*\bscore\b[^\n]*\)/) }
  fix "Use ShopTheLook::Suggestion with source, reasons, and commerce_key so a commercial recommendation is attributable and explainable."
  bad "Suggestion.new(title, merchant, url, "remote", score)"
  good "Suggestion.new(title, merchant, url, "brgen", score, reasons, commerce_key)"
end
