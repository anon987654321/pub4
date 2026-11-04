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

  # Three dots; lit dots take their own level colour (1 mint-500 Mild, 2 gold
  # Middels, 3 pom Sterk!) so the scale reads at a glance.
  # SCSS contract: .heat-dots > .heat-dot.heat-1|heat-2|heat-3 + .is-lit.
  def heat_dots(item)
    heat = item.heat.to_i.clamp(0, 3)
    dots = (1..3).map do |level|
      classes = ["heat-dot", "heat-#{level}"]
      classes << "is-lit" if level <= heat
      tag.span("", class: classes.join(" "))
    end
    label = t("menu.heat.#{heat}")
    tag.span(safe_join(dots), class: "heat-dots", "aria-label": label, title: label)
  end

  # Flag-free origin chip ("Damaskus"); the two-sentence story from
  # origins.<origin> rides along as the title tooltip.
  def origin_chip(item)
    origin = item.origin.to_s
    tag.span(t("menu.origin_chip", origin: origin_label(origin)),
             class: "chip chip-origin",
             title: t(origin_story_key(origin)))
  end

  # State chip colours per APP_SPEC §7: placed mint, confirmed gold,
  # preparing gold-deep, ready mint-700, delivered ink-soft, cancelled pom.
  # SCSS contract: .state-chip.state-<state>.
  def state_chip(order)
    state = order.state.to_s
    tag.span(t("orders.states.#{state}"), class: "state-chip state-#{state}")
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
