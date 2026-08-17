# frozen_string_literal: true

# Maps brgen marketplace category slugs / names → Google product taxonomy IDs.
#
# google_product_category accepts either the numeric id or the full path string.
# Prefer numeric id (stable, shorter).
#
# Official taxonomy (with ids):
#   https://www.google.com/basepages/producttype/taxonomy-with-ids.en-US.txt
# Version pinned in comments when you vendor a snapshot under data/.
#
# Strategy:
#   1. Exact slug match in MAP
#   2. Normalized name match
#   3. Optional parent fallback
#   4. nil → omit attribute (Google may still serve; category helps quality)
#
# Only allowlisted marketplace categories should be curated for Merchant Center.
# Unmapped categories must not be fed (see curation rules).
module GoogleProductTaxonomy
  # Top-level and common city-marketplace nodes (taxonomy 2021-09-21).
  # Expand as brgen categories stabilize.
  MAP = {
    # Apparel
    "clothing" => 1604,
    "clothes" => 1604,
    "apparel" => 166,
    "fashion" => 166,
    "shoes" => 187,          # Apparel & Accessories > Shoes
    "bags" => 5181,          # Luggage & Bags (close enough; refine later)
    "accessories" => 166,

    # Home
    "home" => 536,           # Home & Garden
    "home-garden" => 536,
    "furniture" => 436,
    "kitchen" => 638,        # often under Home & Garden > Kitchen & Dining — refine if needed
    "garden" => 536,

    # Electronics
    "electronics" => 222,
    "phones" => 267,         # Electronics > Communications > Telephony (approx; refine)
    "computers" => 278,      # refine against local taxonomy snapshot
    "audio" => 223,          # Electronics > Audio

    # Sports / outdoor (Bergen-relevant)
    "sports" => 988,         # Sporting Goods
    "outdoor" => 988,
    "sporting-goods" => 988,
    "bicycles" => 988,       # prefer deeper node when catalog is clearer

    # Kids
    "baby" => 537,           # Baby & Toddler
    "kids" => 1239,          # Toys & Games as soft fallback for mixed kids listings
    "toys" => 1239,

    # Health / beauty
    "health" => 469,
    "beauty" => 469,
    "health-beauty" => 469,

    # Pets
    "pets" => 2,             # Animals & Pet Supplies > Pet Supplies
    "pet-supplies" => 2,

    # Media
    "books" => 784,          # Media > Books (verify in snapshot)
    "media" => 783,
    "music" => 783,

    # Vehicles parts only — full vehicles often restricted
    "auto-parts" => 888,
    "vehicle-parts" => 888,

    # Office / hobby
    "office" => 922,
    "art" => 367,            # Arts & Entertainment
    "hobby" => 367,

    # Default catch-alls — use sparingly; prefer excluding from feed
    "other" => nil,
    "misc" => nil,
    "services" => nil        # services are not Shopping products
  }.freeze

  # Deeper overrides when you know a better node (optional second pass).
  DEEP = {
    "bicycle" => 1026,       # example — replace with id from your taxonomy snapshot
    "ski" => 988,
    "camera" => 141          # Cameras & Optics
  }.freeze

  class << self
    def id_for(category)
      return nil if category.nil?

      key = normalize(category)
      return DEEP[key] if DEEP.key?(key) && DEEP[key]

      MAP.fetch(key) do
        # try singular / plural light normalization
        alt = key.end_with?("s") ? key[0...-1] : "#{key}s"
        MAP[alt]
      end
    end

    def path_for(category, taxonomy_lines: nil)
      id = id_for(category)
      return nil if id.nil?
      return id.to_s unless taxonomy_lines

      line = taxonomy_lines.find { |l| l.start_with?("#{id} - ") }
      line ? line.split(" - ", 2).last.to_s.strip : id.to_s
    end

    def normalize(category)
      category.to_s.strip.downcase.tr(" ", "-").gsub(/_/, "-")
    end

    # Load official file once if vendored at data/google_product_taxonomy.txt
    def load_taxonomy(path)
      File.readlines(path, chomp: true).reject { |l| l.empty? || l.start_with?("#") }
    end
  end
end
