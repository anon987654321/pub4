# frozen_string_literal: true

# Maps a curated marketplace listing → Merchant API productAttributes hash
# suitable for GoogleMerchantClient.insert_product! / patch_product!.
#
# listing is expected to respond to at least:
#   id, title, description, price_cents, currency, condition,
#   primary_image_url, canonical_url, category_slug (or category),
#   brand (optional), gtin (optional), availability (optional)
module MerchantOfferMapper
  module_function

  def offer_id(listing)
    "brgen-#{listing.id}"
  end

  def attributes_for(listing)
    price_units = listing.price_cents.to_i
    currency = (listing.currency.presence || "NOK").to_s.upcase
    availability = normalize_availability(listing)
    condition = normalize_condition(listing)

    attrs = {
      title: listing.title.to_s.strip.truncate(150),
      description: listing.description.to_s.strip.truncate(5000),
      link: listing.canonical_url.to_s,
      image_link: listing.primary_image_url.to_s,
      availability: availability,
      condition: condition,
      price: {
        amount_micros: price_units * 10_000, # cents → micros (1 currency unit = 1_000_000 micros)
        currency_code: currency
      }
    }

    brand = listing.try(:brand).presence || listing.try(:seller_name).presence
    attrs[:brand] = brand if brand.present?

    gtin = listing.try(:gtin).presence
    attrs[:gtin] = gtin if gtin.present?

    cat = GoogleProductTaxonomy.id_for(listing.try(:category_slug) || listing.try(:category))
    attrs[:google_product_category] = cat.to_s if cat

    attrs
  end

  def normalize_availability(listing)
    return "out_of_stock" if listing.try(:sold?) || listing.try(:unpublished?)
    return listing.availability.to_s if listing.try(:availability).present?

    "in_stock"
  end

  def normalize_condition(listing)
    raw = listing.try(:condition).to_s.downcase
    return "used" if raw.match?(/used|second|pre-?owned/)
    return "refurbished" if raw.match?(/refurb/)

    "new"
  end
end
