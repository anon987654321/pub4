# frozen_string_literal: true

# schema.org Restaurant and Menu for the menu page, read by search engines
# and answer surfaces: the kitchen's address, phone, hours and price range,
# and every dish on today's menu with its price.
module StructuredDataHelper
  # The kitchen's own wording ("Man–Fre 11–21 · Lør–Søn 14–21") in
  # schema.org's ("Mo-Fr 11:00-21:00"); a span it cannot read is left out.
  SCHEMA_DAYS = { "Man" => "Mo", "Tir" => "Tu", "Ons" => "We", "Tor" => "Th", "Fre" => "Fr", "Lør" => "Sa",
                  "Søn" => "Su" }.freeze
  # Seeds write an en dash; a kitchen row saved while copy was ASCII (2026-11-05/06) carries a hyphen.
  HOURS_SPAN = /(\p{L}{3})[-\u2013](\p{L}{3}) (\d{1,2})[-\u2013](\d{1,2})/

  def restaurant_json_ld(kitchen, categories)
    data = restaurant_facts(kitchen).merge(
      priceRange: price_range(categories),
      hasMenu: { "@type": "Menu", hasMenuSection: categories.map { |category| menu_section(category) } }
    )
    tag.script(ERB::Util.json_escape(data.compact.to_json).html_safe, type: "application/ld+json")
  end

  def schema_opening_hours(text)
    spans = text.to_s.scan(HOURS_SPAN).filter_map do |from, to, opens, closes|
      next unless SCHEMA_DAYS.key?(from) && SCHEMA_DAYS.key?(to)

      format("%s-%s %02d:00-%02d:00", SCHEMA_DAYS[from], SCHEMA_DAYS[to], opens.to_i, closes.to_i)
    end
    spans.presence
  end

  private

  def restaurant_facts(kitchen)
    street, place = kitchen.address.to_s.split(", ", 2)
    { "@context": "https://schema.org", "@type": "Restaurant", name: t("app.name"), servesCuisine: t("app.cuisine"),
      url: root_url, telephone: kitchen.phone, openingHours: schema_opening_hours(kitchen.opening_hours),
      address: { "@type": "PostalAddress", streetAddress: street, postalCode: kitchen.postcode,
                 addressLocality: place.to_s.split.last, addressCountry: "NO" } }
  end

  def price_range(categories)
    prices = categories.flat_map(&:available_items).map(&:price_ore)
    "#{money(prices.min)}–#{money(prices.max)}" if prices.any?
  end

  def menu_section(category)
    { "@type": "MenuSection", name: category.localized(:name),
      hasMenuItem: category.available_items.map { |item| menu_item_facts(item) } }
  end

  def menu_item_facts(item)
    { "@type": "MenuItem", name: item.localized(:name), description: item.localized(:description).presence,
      offers: { "@type": "Offer", price: format("%.2f", item.price_ore / 100.0), priceCurrency: "NOK" } }.compact
  end
end
