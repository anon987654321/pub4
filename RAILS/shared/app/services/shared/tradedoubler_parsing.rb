# frozen_string_literal: true

module Shared
  # Turning a TradeDoubler response into a Deal.
  #
  # Split out of tradedoubler.rb when that file passed its file-length ceiling.
  # The seam is what the methods touch: nothing here makes a request or reads a
  # token — it takes a body that has already arrived and works out which of the
  # three shapes TradeDoubler answers in it happens to be (official nested
  # offers, flat legacy fields, and an XML-ish variant), then reads a price, a
  # stock flag and an image out of it. The half left behind fetches, caches,
  # imports and upserts.
  #
  # That split is also where the bugs live: every one of these methods exists
  # because a feed came back in a shape the last one did not handle.
  #
  # `extend`ed by Tradedoubler, so every call site keeps calling
  # Shared::Tradedoubler.parse / .to_deal / .row_to_deal unchanged.
  # Tradedoubler::Deal is qualified rather than bare: constant lookup is
  # lexical, so a module that is extended into Tradedoubler does not see
  # Tradedoubler's constants. Same lesson the CDP framing split taught, and
  # the same failure shape if it is missed — NameError at the first call,
  # not at load.
  module TradedoublerParsing
    # Official + legacy product shapes (nested offers, flat fields, XML-ish).
    def parse(body)
      Array(extract_products(body)).filter_map do |product|
        next unless product.is_a?(Hash)

        offer = primary_offer(product)
        fields = product["fields"]
        fields = fields.is_a?(Hash) ? fields : {}
        dig = lambda do |*keys|
          keys.filter_map do |k|
            product[k] || fields[k] || (offer.is_a?(Hash) ? offer[k] : nil)
          end.first
        end

        price_raw, currency = price_and_currency(offer, dig)

        {
          external_id: dig.call("productId", "id", "productID", "sourceProductId", "asin").to_s.presence,
          title: dig.call("name", "productName", "title").to_s.presence,
          description: dig.call("description", "productDescription", "shortDescription").to_s.truncate(500),
          merchant: product.dig("program", "name").presence ||
                    dig.call("programName", "merchantName", "advertiser").to_s.presence,
          program_id: (product.dig("program", "id") || dig.call("programId")).to_s.presence,
          price_cents: to_cents(price_raw),
          currency: currency.to_s.presence,
          image_url: image_url(product, dig).to_s.presence,
          click_url: dig.call("productUrl", "clickUrl", "trackingUrl").to_s.presence,
          category: category_name(product) || dig.call("categoryName", "category").to_s.presence,
          in_stock: in_stock?(dig),
          feed_id: dig.call("feedId"),
        }
      end
    end

    # productImage is a hash in the official shape and a bare string in the
    # legacy one, and the legacy feeds disagree with each other about the key.
    def image_url(product, dig)
      image = product["productImage"]
      return image["url"] if image.is_a?(Hash)

      dig.call("imageUrl", "productImage", "imageURL")
    end

    # Price arrives three ways: as a hash carrying its own currency, as a bare
    # value with the currency alongside it, or only inside the offer's price
    # history. The history fills gaps rather than overriding — a current price
    # beats a historical one.
    def price_and_currency(offer, dig)
      raw = dig.call("price", "Price", "priceValue")
      if raw.is_a?(Hash)
        currency = raw["currency"].presence
        raw = raw["value"]
      else
        currency = dig.call("currency", "Currency")
      end

      latest = offer["priceHistory"].last if offer.is_a?(Hash) && offer["priceHistory"].is_a?(Array)
      return [ raw, currency ] unless latest.is_a?(Hash)

      historical = latest["price"] || latest
      if historical.is_a?(Hash)
        [ raw || historical["value"], currency || historical["currency"] ]
      else
        [ raw || historical, currency ]
      end
    end

    # Absent availability is treated as in stock, because most feeds omit the
    # field entirely for stocked items.
    def in_stock?(dig)
      case dig.call("availability", "inStock").to_s.downcase
      when "out of stock", "outofstock", "false", "0", "n", "no" then false
      else ![ false, "false", "0", 0 ].include?(dig.call("inStock"))
      end
    end

    def extract_products(body)
      return [] unless body.is_a?(Hash) || body.is_a?(Array)
      return body if body.is_a?(Array)

      products = body["products"] || body["product"] || body["items"]
      products = products["product"] if products.is_a?(Hash) && products.key?("product")
      products = [ products ] if products.is_a?(Hash)
      products
    end

    def primary_offer(product)
      offers = product["offers"]
      return offers.first if offers.is_a?(Array) && offers.first.is_a?(Hash)
      return offers if offers.is_a?(Hash)

      nil
    end

    def category_name(product)
      cats = product["categories"]
      return nil unless cats.is_a?(Array) && cats.first.is_a?(Hash)

      cats.first["name"].presence || cats.first["tdCategoryName"].presence
    end

    def to_cents(value)
      return nil if value.blank?
      return (value * 100).round if value.is_a?(Numeric)

      numeric = value.to_s.gsub(/[^0-9.,-]/, "").tr(",", ".")
      return nil if numeric.blank?

      (numeric.to_f * 100).round
    end

    def to_deal(product)
      Tradedoubler::Deal.new(
        title: product.title.to_s,
        description: product.description.to_s.truncate(120),
        price: product.price.to_s,
        currency: product.currency.to_s,
        image_url: product.image_url.to_s,
        click_url: product.click_url.to_s,
        merchant: product.merchant.to_s,
        placeholder: product.placeholder?,
      )
    end

    def row_to_deal(row)
      Tradedoubler::Deal.new(
        title: row[:title].to_s,
        description: row[:description].to_s.truncate(120),
        price: row[:price_cents] ? format("%.2f", row[:price_cents] / 100.0) : "",
        currency: row[:currency].to_s,
        image_url: row[:image_url].to_s,
        click_url: row[:click_url].to_s,
        merchant: row[:merchant].to_s,
        placeholder: false,
      )
    end
  end
end
