# frozen_string_literal: true

# Structured data for amber's public pages.
#
# The shared `SchemaHelper` covers most of this, but two of its assumptions do
# not hold here:
#
#   * `item_list_schema` and `product_schema` build URLs with `url_for(item)`,
#     which for an amber Item resolves to `/items/:id` — behind authentication.
#     A crawler following that reaches the sign-in page, so the public demo
#     wardrobe needs its own public URLs.
#   * `product_schema` describes a marketplace listing, with an Offer, a price
#     and an availability. A garment in someone's closet is not for sale.
#
# Everything else — Article on posts, Organization in the layout — goes through
# the shared helper unchanged.
module AmberSchemaHelper
  DEMO_LIST_LIMIT = 30

  def demo_item_list_schema(items, title:)
    listed = items.first(DEMO_LIST_LIMIT)

    {
      "@context" => "https://schema.org",
      "@type" => "ItemList",
      "name" => title,
      "numberOfItems" => listed.size,
      "itemListElement" => listed.map.with_index(1) do |item, position|
        {
          "@type" => "ListItem",
          "position" => position,
          "item" => demo_garment_schema(item, context: false),
        }
      end,
    }.compact
  end

  # A Product without an Offer: schema.org allows it, and it is the honest
  # description of a garment being shown rather than sold.
  def demo_garment_schema(item, context: true)
    {
      "@context" => ("https://schema.org" if context),
      "@type" => "Product",
      "name" => item.title,
      "url" => demo_wardrobe_item_url(item),
      "category" => item.category.presence,
      "color" => schema_colour(item),
      "material" => item.material.presence,
      "brand" => ({ "@type" => "Brand", "name" => item.brand } if item.brand.present?),
      "image" => demo_photo_url(item),
    }.compact
  end

  private

  # Item#color holds either a name or a hex value written by the dominant-colour
  # extractor. A hex string is not a colour name and does not belong in schema.
  def schema_colour(item)
    colour = item.color.to_s.strip
    colour.presence unless colour.start_with?("#")
  end

  def demo_photo_url(item)
    return nil unless item.photos.attached?

    url_for(item.photos.first)
  rescue StandardError
    nil
  end
end
