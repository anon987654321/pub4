# frozen_string_literal: true

# Presentation helpers shared across the app (APP_SPEC §6/§7). Money is
# integer øre everywhere; the chip helpers map straight onto the §1/§7
# palette (mint/gold/pom) that the stylesheet owns.
module ApplicationHelper
  # Food photos — one generated studio shot per seeded dish (app/assets/
  # images/food, provenance in food/provenance.json). Keyed by the menu
  # item's Norwegian name (the seeds are the catalog's source of truth), so
  # no schema drift: an item without a photo keeps its emoji tile.
  FOOD_PHOTOS = {
    "Damaskus Kylling Shawarma" => "food/damaskus-kylling-shawarma.jpg",
    "Beirut Lam Shawarma" => "food/beirut-lam-shawarma.jpg",
    "Berlin Gemüse Kebap" => "food/berlin-gemuse-kebap.jpg",
    "Adana Sterk Dürum" => "food/adana-sterk-durum.jpg",
    "Bergen Kebab-i-Dürum" => "food/bergen-kebab-i-durum.jpg",
    "Dubai Gatens Shawarma" => "food/dubai-gatens-shawarma.jpg",
    "Blomkål-Pita Miznon-stil" => "food/blomkal-pita.jpg",
    "Bursa İskender" => "food/bursa-iskender.jpg",
    "Gaziantep Ali Nazik" => "food/gaziantep-ali-nazik.jpg",
    "Familie Fest-Mezze" => "food/familie-fest-mezze.jpg",
    "Stockholm Kebabpizza — helg" => "food/stockholm-kebabpizza.jpg",
    "Sydney Snackpack HSP" => "food/sydney-snackpack-hsp.jpg",
    "Hvitløks-Pommes" => "food/hvitloks-pommes.jpg",
    "Halloumi-Pommes" => "food/halloumi-pommes.jpg",
    "Kısır Bulgursal" => "food/kisir-bulgursal.jpg",
    "Syltebolle" => "food/syltebolle.jpg",
    "Ayran" => "food/ayran.jpg",
    "Şalgam" => "food/salgam.jpg",
    "Tamarind-drikk" => "food/tamarind-drikk.jpg",
    "Jallab" => "food/jallab.jpg",
    "Myntesitronlimonade" => "food/myntesitronlimonade.jpg",
    "Baklava fra Gaziantep" => "food/baklava.jpg",
    "Knefeh fra Damaskus" => "food/knefeh.jpg",
    "Ma'moul" => "food/mamoul.jpg",
    "Damascy Boss-boks" => "food/damascy-boss-boks.jpg"
  }.freeze

  # The item's photo asset path, or nil when the dish has none or is gone
  # (views fall back to the emoji tile).
  def food_photo(item)
    FOOD_PHOTOS[item&.name]
  end

  # The dish's photo as a picture: WebP at 320 and 640 px for the browsers
  # that take it, the JPEG otherwise. Width and height reserve its box, and
  # decoding stays off the main thread. Nil without a photo (views fall back
  # to the emoji tile).
  FOOD_PHOTO_WIDTHS = [320, 640].freeze

  def food_picture(item, size:, **options)
    photo = food_photo(item) or return
    base = photo.delete_suffix(".jpg")
    srcset = FOOD_PHOTO_WIDTHS.map { |width| "#{image_path("#{base}-#{width}.webp")} #{width}w" }.join(", ")
    tag.picture do
      tag.source(type: "image/webp", srcset:, sizes: "#{size}px") +
        image_tag(photo, alt: "", width: size, height: size, decoding: "async", **options)
    end
  end

  # money(1500) → "15 kr" — whole øre render without decimals; anything with
  # a remainder falls back to Norwegian comma decimals ("15,50 kr").
  def money(ore)
    kroner, rester = ore.to_i.divmod(100)
    rester.zero? ? "#{kroner} kr" : format("%d,%02d kr", kroner, rester)
  end

  # Opens an address in the phone's maps app (Google Maps' cross-platform
  # search URL), for the courier's stops.
  def map_search_url(address, postcode)
    "https://www.google.com/maps/search/?api=1&query=#{ERB::Util.url_encode("#{address}, #{postcode}")}"
  end

  # A form field's server-side error, rendered beside the field and named
  # by its aria-describedby (field_error_aria), or nothing when it passed.
  def field_error(errors, field)
    message = errors.to_h[field]
    tag.p(message, id: "#{field}_error", class: "field-error") if message
  end

  def field_error_aria(errors, field)
    errors.to_h[field] ? { describedby: "#{field}_error", invalid: true } : {}
  end

  # Three dots, the lit ones in the level's colour (1 Mild, 2 Middels,
  # 3 Sterk!), and the level in words — read as "Styrke: Mild". Nothing for
  # a dish without heat. SCSS: .heat.heat-N > .heat-dot.on, .heat-label.
  def heat_dots(item)
    heat = item.heat.to_i.clamp(0, 3)
    return if heat.zero?

    words = [tag.span("#{t('menu.heat_label')}:", class: "visually-hidden"),
             tag.span(t("menu.heat.#{heat}"), class: "heat-label")]
    tag.span(safe_join([words.first, *heat_dot_spans(heat), words.last]), class: "heat heat-#{heat}")
  end

  def heat_dot_spans(heat)
    Array.new(3) { |dot| tag.span(class: ["heat-dot", ("on" if dot < heat)], "aria-hidden": true) }
  end

  # Flag-free origin badge ("Fra Damaskus"), or nothing without an origin.
  def origin_chip(item)
    return if item.origin.blank?

    tag.span(t("menu.origin_chip", origin: origin_label(item.origin)), class: "badge")
  end

  # The menu's own badges on a dish (signature, veg, sharing, secret, deal),
  # one span each in their words; unknown badges are left out.
  MENU_BADGES = %w[signature veg sharing secret deal].freeze

  def badge_tags(item)
    badges = item.badges.to_s.split(",").map(&:strip) & MENU_BADGES
    safe_join(badges.map { |badge| tag.span(t("menu.badges.#{badge}"), class: "badge badge-#{badge}") })
  end

  # One spelling for the order list and the order page, so a state's colour
  # cannot drift between them. SCSS: .state-chip.state-<state>.
  def state_chip(order)
    tag.span(t("orders.states.#{order.state}"), class: "state-chip state-#{order.state}")
  end

  # "tel_aviv" / "Tel Aviv" → "origins.tel_aviv" (APP_SPEC §10 keys).
  def origin_story_key(origin)
    "origins.#{origin.to_s.parameterize.underscore}"
  end

  # "tel_aviv" → "Tel Aviv" — proper nouns render as-is in either locale.
  def origin_label(origin)
    origin.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
  end
end
