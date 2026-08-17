# frozen_string_literal: true

module Brgen
  # Placeholder affiliate inventory, for demoing the deals surface before
  # brgen.no is an approved TradeDoubler publisher.
  #
  # Every row is written with placeholder: true, which Shared::AffiliateProduct.real
  # excludes. That flag is the whole point: seed data that looked like real
  # affiliate inventory would be indistinguishable from payable inventory in
  # reporting, and someone would eventually reconcile a payout against it.
  #
  # click_url points at the merchant's own Norwegian storefront, NOT a fabricated
  # tracking link — an invented affiliate deep link would either 404 or, worse,
  # look like it was attributing clicks to an account that doesn't exist.
  module AffiliatePlaceholders
    SOURCE = "tradedoubler"

    # Real Norwegian retailers that genuinely run affiliate programmes in the
    # Nordics, so the merchant names read correctly to a Bergen visitor.
    PRODUCTS = [
      { external_id: "ph-elkjop-airpods", title: "Apple AirPods Pro (2. gen)",
        merchant: "Elkjøp", price_cents: 2_790_00, currency: "NOK",
        category: "electronics", url: "https://www.elkjop.no/",
        description: "Aktiv støydemping og adaptiv transparens." },
      { external_id: "ph-elkjop-tv", title: "Samsung 55\" QLED 4K",
        merchant: "Elkjøp", price_cents: 7_990_00, currency: "NOK",
        category: "electronics", url: "https://www.elkjop.no/",
        description: "Quantum Dot-panel, 120 Hz, tre HDMI 2.1." },
      { external_id: "ph-power-laptop", title: "Lenovo IdeaPad Slim 5",
        merchant: "Power", price_cents: 8_490_00, currency: "NOK",
        category: "electronics", url: "https://www.power.no/",
        description: "16 GB RAM, 512 GB SSD, 14-tommers OLED." },
      { external_id: "ph-xxl-jakke", title: "Bergans Microlight regnjakke",
        merchant: "XXL Sport", price_cents: 1_499_00, currency: "NOK",
        category: "clothing", url: "https://www.xxl.no/",
        description: "Pakkbar skalljakke — laget for vestlandsvær." },
      { external_id: "ph-xxl-sko", title: "Salomon Speedcross 6",
        merchant: "XXL Sport", price_cents: 1_699_00, currency: "NOK",
        category: "clothing", url: "https://www.xxl.no/",
        description: "Grov såle for våt sti og gjørme." },
      { external_id: "ph-jernia-kjele", title: "Jernia stekepanne 28 cm",
        merchant: "Jernia", price_cents: 599_00, currency: "NOK",
        category: "home", url: "https://www.jernia.no/",
        description: "Støpejern, tåler induksjon og stekeovn." },
      { external_id: "ph-komplett-skjerm", title: "Dell UltraSharp 27\" USB-C",
        merchant: "Komplett", price_cents: 4_290_00, currency: "NOK",
        category: "electronics", url: "https://www.komplett.no/",
        description: "QHD, 90 W strøm over ett USB-C-kabel." },
      { external_id: "ph-adlibris-bok", title: "Bergen — en byhistorie",
        merchant: "Adlibris", price_cents: 399_00, currency: "NOK",
        category: "books", url: "https://www.adlibris.com/no",
        description: "Innbundet, rikt illustrert." },
      { external_id: "ph-clas-verktoy", title: "Clas Ohlson skrutrekkersett, 42 deler",
        merchant: "Clas Ohlson", price_cents: 349_00, currency: "NOK",
        category: "home", url: "https://www.clasohlson.com/no",
        description: "Bits for det meste rundt huset." },
      { external_id: "ph-sport1-sykkel", title: "Sykkellås, hardened stål",
        merchant: "Sport 1", price_cents: 699_00, currency: "NOK",
        category: "vehicles", url: "https://www.sport1.no/",
        description: "Bøylelås med monteringsbrakett." }
    ].freeze

    module_function

    def seed!(market: "NO")
      return 0 unless Shared::AffiliateProduct.table_exists?

      PRODUCTS.count do |row|
        Shared::AffiliateProduct.upsert_from_feed!(
          source: SOURCE,
          external_id: row[:external_id],
          title: row[:title],
          description: row[:description],
          merchant: row[:merchant],
          price_cents: row[:price_cents],
          currency: row[:currency],
          image_url: nil,
          click_url: row[:url],
          category: row[:category],
          market: market,
          in_stock: true,
          placeholder: true
        )
        true
      end
    end
  end
end
