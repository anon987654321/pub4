# frozen_string_literal: true

namespace :affiliate do
  desc "Import TradeDoubler products into AffiliateProduct (needs TRADEDOUBLER_TOKEN)"
  task :import, [ :category ] => :environment do |_, args|
    unless Tradedoubler.configured?
      warn <<~MSG
        TRADEDOUBLER_TOKEN is not set — nothing imported.

        brgen.no must be an approved TradeDoubler publisher first, and that is a
        manual process:
          1. Apply as a publisher; get the site approved.
          2. Apply to each advertiser programme separately.
        Then set TRADEDOUBLER_TOKEN (and TRADEDOUBLER_MARKET, default NO).

        For a populated sidebar in the meantime:
          rake affiliate:seed_placeholders
      MSG
      exit 1
    end

    written = Tradedoubler.import!(category: args[:category])
    puts "affiliate:import — #{written} product(s) upserted for market #{Tradedoubler.market}"
    puts "  total live rows: #{AffiliateProduct.sellable.real.count}"
  end

  desc "Report affiliate inventory health (counts, staleness, placeholders)"
  task health: :environment do
    total = AffiliateProduct.count
    puts "affiliate_products: #{total} row(s)"
    puts "  live (in stock, seen within #{AffiliateProduct::STALE_AFTER.inspect}): #{AffiliateProduct.sellable.count}"
    puts "  real: #{AffiliateProduct.real.count}   placeholder: #{AffiliateProduct.where(placeholder: true).count}"
    puts "  stale: #{AffiliateProduct.where.not(id: AffiliateProduct.fresh).count}"
    puts "  token configured: #{Tradedoubler.configured?}"
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
