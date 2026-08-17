# frozen_string_literal: true

# Amazon-specific affiliate tasks. Loaded alongside affiliate.rake.
namespace :affiliate do
  desc "Show Amazon Associates configuration (tags + Creators API readiness)"
  task amazon_status: :environment do
    puts "Amazon market default: #{Shared::AmazonAssociates.market}"
    puts "Creators API configured?: #{Shared::AmazonAssociates.configured?}"
    puts "  client_id:     #{Shared::AmazonAssociates.client_id.present?}"
    puts "  client_secret: #{Shared::AmazonAssociates.client_secret.present?}"
    puts "  version:       #{Shared::AmazonAssociates.version}"
    puts "  partner_tag:   #{Shared::AmazonAssociates.partner_tag.inspect}"
    puts "  marketplace:   #{Shared::AmazonAssociates.marketplace_host}"
    puts
    puts "Per-marketplace tags (AMAZON_ASSOCIATE_TAG_<CC>):"
    Shared::AmazonMarketplace.configured_countries.each do |cc|
      tag = Shared::AmazonMarketplace.tag_for(cc)
      host = Shared::AmazonMarketplace.host_for(cc)
      puts "  #{cc} → #{host}  tag=#{tag}"
    end
    if Shared::AmazonMarketplace.configured_countries.empty?
      puts "  (none set — set e.g. AMAZON_ASSOCIATE_TAG_SE=yoursite-21)"
    end
    puts
    amazon_rows = Shared::AffiliateProduct.where(source: "amazon")
    puts "Shared::AffiliateProduct amazon rows: #{amazon_rows.count} " \
         "(real live: #{amazon_rows.merge(Shared::AffiliateProduct.sellable.real).count})"
  end

  desc "Seed curated Amazon ASINs into Shared::AffiliateProduct with correct marketplace tags (no API needed)"
  task :amazon_seed, [:market] => :environment do |_, args|
    market = (args[:market].presence || ENV.fetch("AMAZON_MARKET", "SE")).upcase
    unless Shared::AmazonAssociates.tag_only_configured?(market)
      warn "No AMAZON_ASSOCIATE_TAG_#{Shared::AmazonMarketplace.country_for(market)} set — cannot tag links."
      exit 1
    end

    # Default Nordic-friendly seed set. Replace/extend with real high-intent ASINs
    # for your audience. Titles are placeholders until Creators API enriches them.
    seeds = ENV["AMAZON_SEED_ASINS"].to_s.split(",").map(&:strip).reject(&:blank?)
    if seeds.empty?
      warn <<~MSG
        Set AMAZON_SEED_ASINS=B0XXXX,B0YYYY (comma-separated) or pass a Ruby list in console:

          Shared::AmazonAssociates.seed_asins!([
            { asin: "B0XXXX", title: "Product name", market: "#{market}", category: "electronics" },
          ])

        No default ASINs are hard-coded — wrong products earn nothing and look spammy.
      MSG
      exit 1
    end

    entries = seeds.map { |asin| { asin: asin, market: market } }
    written = Shared::AmazonAssociates.seed_asins!(entries, default_market: market)
    puts "affiliate:amazon_seed — #{written} product(s) upserted for market=#{market}"
    puts "  live amazon rows: #{Shared::AffiliateProduct.where(source: 'amazon').merge(Shared::AffiliateProduct.sellable).count}"
  end
end
