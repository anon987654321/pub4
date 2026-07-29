# frozen_string_literal: true

namespace :affiliate do
  desc "Import affiliate products from every configured network"
  task :import, [ :category ] => :environment do |_, args|
    configured = Affiliate.configured_networks
    if configured.empty?
      warn <<~MSG
        No affiliate network is configured — nothing imported.

        TradeDoubler: brgen.no must be an approved publisher first, and that is
        a manual, two-step process (apply as publisher, then to each advertiser
        programme). Then set TRADEDOUBLER_TOKEN (+TRADEDOUBLER_MARKET, default NO).

        Amazon Associates: join the programme for a locale that ships to Norway
        (there is no amazon.no), make three qualifying sales within 180 days,
        and only then are PA-API credentials issued. Then set
        AMAZON_ACCESS_KEY, AMAZON_SECRET_KEY and AMAZON_PARTNER_TAG.

        For a populated sidebar in the meantime:
          rake affiliate:seed_placeholders
      MSG
      exit 1
    end

    results = Affiliate.import_all!(category: args[:category])
    results.each { |network, written| puts "affiliate:import — #{network}: #{written} product(s) upserted" }
    puts "  total live rows: #{AffiliateProduct.sellable.real.count}"
  end

  desc "Report affiliate inventory health (counts, staleness, placeholders)"
  task health: :environment do
    total = AffiliateProduct.count
    puts "affiliate_products: #{total} row(s)"
    puts "  live (in stock, seen within #{AffiliateProduct::STALE_AFTER.inspect}): #{AffiliateProduct.sellable.count}"
    puts "  real: #{AffiliateProduct.real.count}   placeholder: #{AffiliateProduct.where(placeholder: true).count}"
    puts "  stale: #{AffiliateProduct.where.not(id: AffiliateProduct.fresh).count}"
    Affiliate.networks.each { |n| puts "  #{n.name}: configured=#{n.configured?}" }
    AffiliateProduct.group(:source).count.each { |source, count| puts "  #{source}: #{count}" }
  end

  desc "Seed clearly-flagged placeholder affiliate products (no network needed)"
  task seed_placeholders: :environment do
    created = Brgen::AffiliatePlaceholders.seed!
    puts "affiliate:seed_placeholders — #{created} placeholder row(s)."
    puts "These are flagged placeholder: true and are excluded from .real —"
    puts "they demo the surface, they are never payable inventory."
  end

  desc "Delete placeholder rows (run once real import works)"
  task drop_placeholders: :environment do
    deleted = AffiliateProduct.where(placeholder: true).delete_all
    puts "affiliate:drop_placeholders — removed #{deleted} row(s)."
  end
end
