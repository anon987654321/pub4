# frozen_string_literal: true

namespace :affiliate do
  desc "Import affiliate products from every configured network"
  task :import, [ :category ] => :environment do |_, args|
    configured = Shared::Affiliate.configured_networks
    if configured.empty?
      warn <<~MSG
        No affiliate network is configured — nothing imported.

        TradeDoubler: brgen.no must be an approved publisher first, and that is
        a manual, two-step process (apply as publisher, then to each advertiser
        programme). Then set TRADEDOUBLER_TOKEN (+TRADEDOUBLER_MARKET, default NO).
        Optional: TRADEDOUBLER_FEED_IDS, TRADEDOUBLER_IMPORT_MODE=unlimited,
        TRADEDOUBLER_VOUCHERS_TOKEN, TRADEDOUBLER_WEBSITE_ID,
        TRADEDOUBLER_WEBHOOK_SECRET / TRADEDOUBLER_CONVERSIONS_TOKEN.

        Amazon Associates: join the programme for a locale that ships to Norway
        (there is no amazon.no), make three qualifying sales within 180 days,
        and only then are PA-API credentials issued. Then set
        AMAZON_ACCESS_KEY, AMAZON_SECRET_KEY and AMAZON_PARTNER_TAG.

        For a populated sidebar in the meantime:
          rake affiliate:seed_placeholders
      MSG
      exit 1
    end

    results = Shared::Affiliate.import_all!(category: args[:category])
    results.each { |network, written| puts "affiliate:import — #{network}: #{written} product(s) upserted" }
    vouchers = Shared::Tradedoubler.import_vouchers!
    puts "affiliate:import — vouchers: #{vouchers}"
    puts "  total live product rows: #{Shared::AffiliateProduct.sellable.real.count}"
  end

  desc "List TradeDoubler product feeds (needs TRADEDOUBLER_TOKEN)"
  task feeds: :environment do
    unless Shared::Tradedoubler.configured?
      warn "TRADEDOUBLER_TOKEN not set"
      exit 1
    end
    feeds = Shared::Tradedoubler.list_feeds
    if feeds.empty?
      puts "No feeds (not approved / no programmes / API empty)."
    else
      feeds.each do |f|
        puts format(
          "feed=%-8s active=%-5s products=%-8s %s %s %s",
          f.feed_id, f.active, f.product_count, f.currency, f.language, f.name
        )
      end
    end
  end

  desc "Sync TradeDoubler Link Converter script to public/js/td-lc.js"
  task sync_link_converter: :environment do
    unless Shared::Tradedoubler.link_converter_configured?
      warn "Set TRADEDOUBLER_WEBSITE_ID first"
      exit 1
    end
    ok = LinkConverterSyncJob.perform_now
    puts ok ? "synced public/js/td-lc.js" : "sync failed"
    exit(ok ? 0 : 1)
  end

  desc "Report affiliate inventory health (counts, staleness, placeholders)"
  task health: :environment do
    total = Shared::AffiliateProduct.count
    puts "affiliate_products: #{total} row(s)"
    puts "  live (in stock, seen within #{Shared::AffiliateProduct::STALE_AFTER.inspect}): #{Shared::AffiliateProduct.sellable.count}"
    puts "  real: #{Shared::AffiliateProduct.real.count}   placeholder: #{Shared::AffiliateProduct.where(placeholder: true).count}"
    puts "  stale: #{Shared::AffiliateProduct.where.not(id: Shared::AffiliateProduct.fresh).count}"
    if defined?(Shared::AffiliateVoucher) && Shared::AffiliateVoucher.table_exists?
      puts "affiliate_vouchers: #{Shared::AffiliateVoucher.count} (live: #{Shared::AffiliateVoucher.live.count})"
    end
    if defined?(Shared::AffiliateConversion) && Shared::AffiliateConversion.table_exists?
      puts "affiliate_conversions: #{Shared::AffiliateConversion.count} " \
           "(approved: #{Shared::AffiliateConversion.approved.count}, paid: #{Shared::AffiliateConversion.paid.count})"
    end
    Shared::Affiliate.networks.each { |n| puts "  #{n.name}: configured=#{n.configured?}" }
    puts "  link_converter website_id=#{Shared::Tradedoubler.website_id.present?}"
    Shared::AffiliateProduct.group(:source).count.each { |source, count| puts "  #{source}: #{count}" }
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
    deleted = Shared::AffiliateProduct.where(placeholder: true).delete_all
    puts "affiliate:drop_placeholders — removed #{deleted} row(s)."
  end
  desc "Clicks sent vs conversions returned, and the gap between them"
  task :attribution, [ :days ] => :environment do |_, args|
    days = (args[:days] || 7).to_i
    puts PartnerAttributionReport.new(window: days.days).render
  end
end
