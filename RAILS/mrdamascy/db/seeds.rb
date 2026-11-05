# frozen_string_literal: true

# Seeds — the "World tour of kebab" catalog (APP_SPEC §11).
#
# Idempotent: everything is destroyed in FK-safe order, then recreated, so
# `bin/rails db:seed` is always safe to run again.

Review.destroy_all
LoyaltyStamp.destroy_all
OrderItem.destroy_all
Order.destroy_all
CartItem.destroy_all
Cart.destroy_all
Session.destroy_all
ItemOption.destroy_all
MenuItem.destroy_all
MenuCategory.destroy_all
DeliveryZone.destroy_all
PromoCode.destroy_all
User.destroy_all
Kitchen.destroy_all

# Local helper: kr → øre. Money is integer øre everywhere (APP_SPEC §2).
def ore(kr)
  (kr * 100).to_i
end

# --- Kitchen (single row) ---------------------------------------------------

kitchen = Kitchen.create!(
  name: "Mr. Damascy — Danmarksplass",
  slug: "bergen",
  address: "Solheimsgaten 60, 5054 Bergen",
  postcode: "5054",
  phone: "955 55 600",
  opening_hours: "Man–Fre 11–21 · Lør–Søn 14–21",
  opening_hours_en: "Mon–Fri 11am–9pm · Sat–Sun 2pm–9pm",
  weekly_hours: %w[mon tue wed thu fri].index_with { %w[11:00 21:00] }
                                       .merge("sat" => %w[14:00 21:00], "sun" => %w[14:00 21:00]),
  rating: 4.9
)

# --- Delivery zones: postcode, name, fee kr, min basket kr, eta min ---------
# Central Bergen (Vestland). The one outlet is at Danmarksplass (Solheimsgaten
# 60, 5054); the closest codes deliver fastest, outer boroughs cost more and
# take longer.

{
  "5054" => [ "Danmarksplass",    29, 150, 15 ],
  "5003" => [ "Bergen sentrum",   39, 200, 25 ],
  "5004" => [ "Strandgaten",      29, 150, 15 ],
  "5006" => [ "Vågsbunnen",       29, 150, 20 ],
  "5007" => [ "Bergenhus vest",   35, 150, 25 ],
  "5008" => [ "Nøstet",           35, 150, 25 ],
  "5009" => [ "Møhlenpris",       35, 150, 25 ],
  "5015" => [ "Nygård",           39, 200, 30 ],
  "5017" => [ "Årstad",           39, 200, 30 ],
  "5020" => [ "Møllendal",        45, 250, 35 ],
  "5141" => [ "Fyllingsdalen",    49, 300, 40 ],
  "5160" => [ "Laksevåg",         49, 300, 40 ],
  "5221" => [ "Nesttun",          55, 300, 45 ]
}.each do |postcode, (name, fee_kr, min_kr, eta)|
  DeliveryZone.create!(
    postcode: postcode,
    name: name,
    fee_ore: ore(fee_kr),
    min_basket_ore: ore(min_kr),
    eta_minutes: eta
  )
end

# --- Menu categories ---------------------------------------------------------

category_rows = [
  [ "Wraps & Ruller", "Wraps & Rolls", "wraps",     "🌯", 1 ],
  [ "Tallerker",      "Plates",        "tallerker", "🍽️", 2 ],
  [ "Tilbehør",       "Sides",         "tilbehor",  "🍟", 3 ],
  [ "Drikke",         "Drinks",        "drikke",    "🥤", 4 ],
  [ "Desserter",      "Desserts",      "desserter", "🍮", 5 ],
  [ "Bokser",         "Boxes",         "bokser",    "🎁", 6 ]
]
categories = {}
category_rows.each do |name, name_en, slug, emoji, position|
  categories[slug] = kitchen.menu_categories.create!(
    name: name, name_en: name_en, slug: slug, emoji: emoji, position: position
  )
end

# --- Menu items: name, name_en, origin, heat, price kr, emoji, badges, weight_g

item_rows = {
  "wraps" => [
    [ "Damaskus Kylling Shawarma",   "Damascus Chicken Shawarma",     "damaskus",  1, 129, "🌯", "signature",     450,
      "Kylling fra spettet, toum og sylteagurk — Damaskus' egen favoritt." ],
    [ "Beirut Lam Shawarma",         "Beirut Lamb Shawarma",          "beirut",    1, 139, "🥙", nil,             nil,
      "Mager lam med granateple-løk og tarator — Beirut-disiplin." ],
    [ "Berlin Gemüse Kebap",         "Berlin Gemüse Kebap",           "berlin",    1, 139, "🥬", "veg",           nil,
      "Grillet grønnsak og rikelig salat — køens favoritt fra Berlin." ],
    [ "Adana Sterk Dürum",           "Adana Hot Dürum",               "adana",     3, 149, "🔥", nil,             nil,
      "Krydret kjøttfars etter Adana-oppskriften. Sterk!" ],
    [ "Bergen Kebab-i-Dürum",        "Bergen Kebab-i-Dürum",          "bergen",    2, 139, "🧔", "salatbar",      nil,
      "Kvartover-ærlig kebab med salatbar akkurat som hjemme i Bergen." ],
    [ "Dubai Gatens Shawarma",       "Dubai Street Shawarma",         "dubai",     1, 135, "🍟", nil,             nil,
      "Pommes i rullen — gatens beste triks fra Dubai." ],
    [ "Blomkål-Pita Miznon-stil",    "Cauliflower Pita Miznon-style", "tel_aviv",  0, 129, "🥦", "veg,signature", nil,
      "Helstekt blomkål i pita — Miznon-spøken, Tel Aviv." ]
  ],
  "tallerker" => [
    [ "Bursa İskender",              "Bursa İskender",                "bursa",     1, 189, "🧈", "signature",     550,
      "Smør, tomatsaus og yoghurt — 1867-ritualen fra Bursa." ],
    [ "Gaziantep Ali Nazik",         "Gaziantep Ali Nazik",           "gaziantep", 2, 179, "🍆", nil,             nil,
      "Røkt aubergine og yoghurt under kebab, fra UNESCO-byen Gaziantep." ],
    [ "Familie Fest-Mezze",          "Family Feast Mezze",            "damaskus",  1, 449, "🫓", "sharing",       1200,
      "Hele bordets fest: wraps, dips og pommes nok til alle." ],
    [ "Stockholm Kebabpizza — helg", "Stockholm Kebabpizza — weekend", "stockholm", 2, 169, "🍕", nil,            nil,
      "Kebab på pizza — Stockholms oppfinnelse. Kun i helgene." ],
    [ "Sydney Snackpack HSP",        "Sydney Snackpack HSP",          "sydney",    2, 149, "🍟", "secret",        nil,
      "Chips, kjøtt, ost og gravy — nattens ritual fra Sydney." ]
  ],
  "tilbehor" => [
    [ "Hvitløks-Pommes",  "Garlic Fries",     "bergen",    0, 59, "🍟", nil,  nil, "Pommes badet i toum." ],
    [ "Halloumi-Pommes",  "Halloumi Fries",   "bergen",    0, 79, "🧀", nil,  nil, "Saltstekt halloumi over pommes." ],
    [ "Kısır Bulgursal",  "Kısır Bulgur Salad", "gaziantep", 0, 49, "🥗", "veg", nil, "Syrlig bulgursalat med granateple." ],
    [ "Syltebolle",       "Pickle",           "damaskus",  0, 29, "🥒", nil,  nil, "Én syrisk sylteagurk, kjøkkenets kompliment." ]
  ],
  "drikke" => [
    [ "Ayran",              "Ayran",              "bursa",     0, 35, "🥛", nil, nil, "Saltet yoghurtdrikk — kebabens beste venn." ],
    [ "Şalgam",             "Şalgam",             "adana",     0, 35, "🍅", nil, nil, "Gjæret turnipsdrikk, Adana-stil." ],
    [ "Tamarind-drikk",     "Tamarind Drink",     "damaskus",  0, 39, "🍹", nil, nil, "Søt-sur tamarind, servert kjølig." ],
    [ "Jallab",             "Jallab",             "beirut",    0, 39, "🍇", nil, nil, "Druemelasse, rose og pinjekjerner." ],
    [ "Myntesitronlimonade","Mint Lemonade",      "damaskus",  0, 45, "🍋", nil, nil, "Fersk mynte og sitron, presset i dag." ]
  ],
  "desserter" => [
    [ "Baklava fra Gaziantep", "Baklava from Gaziantep", "gaziantep", 0, 69, "🍯", nil, nil, "Pistasj, honning og mange lag." ],
    [ "Knefeh fra Damaskus",   "Knefeh from Damascus",   "damaskus",  0, 79, "🧀", "signature", nil, "Varm ost, semulegrot og sirup — Damaskus' morgen." ],
    [ "Ma'moul",               "Ma'moul",                "damaskus",  0, 59, "🌰", nil, nil, "Semuliekaker med dadler og valnøtt." ]
  ],
  "bokser" => [
    [ "Damascy Boss-boks", "Damascy Boss Box", "damaskus", 0, 199, "🎁", "deal", nil,
      "Wrap + pommes + drikke + baklava-bite — hele måltidet i én boks." ]
  ]
}

items = {}
photos = YAML.load_file(Rails.root.join("db/food_photos.yml"))
item_rows.each do |slug, rows|
  rows.each_with_index do |(name, name_en, origin, heat, price_kr, emoji, badges, weight_g, description), i|
    items[name] = categories[slug].menu_items.create!(
      name: name,
      name_en: name_en,
      description: description,
      origin: origin,
      heat: heat,
      price_ore: ore(price_kr),
      emoji: emoji,
      badges: badges,
      weight_g: weight_g,
      position: i + 1,
      available: true,
      photo_path: photos[name]
    )
  end
end

# --- Item options -------------------------------------------------------------
# Every wrap: four sauces (all 0 kr), the salatbar (toppings, 0 kr, some on by
# default) and the paid extras. The İskender gets butter/yoghurt extras; the
# Boss-boks gets a drink choice (kind extra).

wraps = [
  "Damaskus Kylling Shawarma", "Beirut Lam Shawarma", "Berlin Gemüse Kebap",
  "Adana Sterk Dürum", "Bergen Kebab-i-Dürum", "Dubai Gatens Shawarma",
  "Blomkål-Pita Miznon-stil"
]

sauces = [
  [ "Toum",               "Toum (garlic sauce)", 0,   true  ],
  [ "Tarator",            "Tarator (tahini sauce)", 0, false ],
  [ "Yoghurt-urt",        "Yoghurt & herbs",     0,   false ],
  [ "Syrisk sterk chili", "Syrian hot chili",    0,   false ]
]
toppings = [
  [ "Salat",      "Salad",      0, true  ],
  [ "Tomat",      "Tomato",     0, true  ],
  [ "Agurk",      "Cucumber",   0, true  ],
  [ "Rødløk",     "Red onion",  0, false ],
  [ "Rødkål",     "Red cabbage", 0, true ],
  [ "Mais",       "Corn",       0, false ],
  [ "Jalapeño",   "Jalapeño",   0, false ],
  [ "Sylteagurk", "Pickles",    0, true  ]
]
extras = [
  [ "Ekstra kjøtt", "Extra meat",    25, false ],
  [ "Dobbel ost",   "Double cheese", 15, false ],
  [ "Ekstra brød",  "Extra bread",   10, false ]
]

def add_options!(menu_item, rows, kind, start:)
  rows.each_with_index do |(name, name_en, price_kr, default_on), i|
    menu_item.item_options.create!(
      name: name,
      name_en: name_en,
      price_ore: ore(price_kr),
      kind: kind,
      default_on: default_on,
      position: start + i
    )
  end
end

wraps.each do |wrap_name|
  wrap = items[wrap_name]
  add_options!(wrap, sauces, "sauce", start: 1)
  add_options!(wrap, toppings, "topping", start: sauces.size + 1)
  add_options!(wrap, extras, "extra", start: sauces.size + toppings.size + 1)
end

add_options!(items["Bursa İskender"], [
  [ "Ekstra smør",    "Extra butter",  10, false ],
  [ "Ekstra yoghurt", "Extra yoghurt", 15, false ]
], "extra", start: 1)

add_options!(items["Damascy Boss-boks"], [
  [ "Ayran i boksen",  "Ayran in the box",  0, false ],
  [ "Şalgam i boksen", "Şalgam in the box", 0, false ],
  [ "Brus i boksen",   "Soft drink in the box", 0, false ]
], "extra", start: 1)

# --- Promo codes --------------------------------------------------------------

{
  "SAHTEIN10" => [ "percent", 10,   0,      "Første bestilling" ],
  "YALLA25" => [ "fixed", 2500,   25000, "Yalla! 25 kr av over 250 kr" ],
  "GRATISLEVERING" => [ "free_delivery", 0, 30000, "Gratis levering over 300 kr" ],
  "FAMILIE15" => [ "percent", 15,  40000,  "15 % på familiebordet over 400 kr" ]
}.each do |code, (kind, value, min_basket_ore, description)|
  PromoCode.create!(
    code: code,
    kind: kind,
    value: value,
    min_basket_ore: min_basket_ore,
    active: true,
    description: description
  )
end

# --- Users ----------------------------------------------------------------------
# OTP mock is fixed at 1234 (SessionsController, APP_SPEC §6) — nothing to seed.

hassan = User.create!(phone: "90000001", name: "Hassan",     role: :admin)
User.create!(phone: "90000002", name: "Umm Yusuf", role: :staff)
User.create!(phone: "90000003", name: "Kader",     role: :courier)
ola = User.create!(
  phone: "90000004", name: "Ola Nordmann", role: :customer,
  default_address: "Nygårdsgaten 12", default_postcode: "5015"
)
# Hassan owns the kitchen story (About page); Umm Yusuf runs the board and
# Kader the courier runs — all three are reachable via role: on users.

# --- Demo realism: Ola has 2 delivered orders + 6 stamps ----------------------

def demo_order(user, kitchen:, placed_at:, promo_code: nil, discount_ore: 0, tip_ore: 0)
  order = Order.create!(
    user: user,
    kitchen: kitchen,
    state: "delivered",
    delivery_mode: "delivery",
    address: user.default_address,
    postcode: user.default_postcode,
    phone: user.phone,
    delivery_fee_ore: 2900,
    discount_ore: discount_ore,
    tip_ore: tip_ore,
    promo_code: promo_code,
    eta_minutes: 20,
    payment_state: "captured",
    payment_steps: 3,
    express: true,
    placed_at: placed_at
  )
  order.update!(vipps_order_id: "mock-#{order.tracking_token}")
  order
end

def add_demo_line(order, menu_item, quantity: 1, options_text: nil, unit_price_ore: nil)
  unit = (unit_price_ore || menu_item.price_ore).to_i
  order.order_items.create!(
    menu_item_id: menu_item.id,
    name: menu_item.name,
    emoji: menu_item.emoji,
    quantity: quantity,
    unit_price_ore: unit,
    options_text: options_text,
    line_total_ore: unit * quantity
  )
end

# Order 1, three weeks ago: two shawarma + tip, no promo.
order_1 = demo_order(ola, kitchen: kitchen, placed_at: 3.weeks.ago, tip_ore: 2000)
add_demo_line(order_1, items["Damaskus Kylling Shawarma"])
add_demo_line(order_1, items["Beirut Lam Shawarma"])
subtotal_1 = order_1.order_items.sum(:line_total_ore)
order_1.update!(
  subtotal_ore: subtotal_1,
  total_ore: subtotal_1 - order_1.discount_ore.to_i + order_1.delivery_fee_ore.to_i + order_1.tip_ore.to_i
)

# Order 2, one week ago: veg kebab + ayran, SAHTEIN10 auto-applied.
order_2 = demo_order(ola, kitchen: kitchen, placed_at: 1.week.ago,
                     promo_code: "SAHTEIN10", discount_ore: 1740)
add_demo_line(order_2, items["Berlin Gemüse Kebap"])
add_demo_line(order_2, items["Ayran"])
subtotal_2 = order_2.order_items.sum(:line_total_ore)
order_2.update!(
  subtotal_ore: subtotal_2,
  total_ore: subtotal_2 - order_2.discount_ore.to_i + order_2.delivery_fee_ore.to_i + order_2.tip_ore.to_i
)

# Six Sahtein stamps: the two delivered orders plus four older visits.
[
  [ order_1, 3.weeks.ago + 1.hour ],
  [ order_2, 1.week.ago + 1.hour ],
  [ nil, 5.weeks.ago ],
  [ nil, 6.weeks.ago ],
  [ nil, 7.weeks.ago ],
  [ nil, 8.weeks.ago ]
].each do |order, awarded_at|
  LoyaltyStamp.create!(user: ola, order: order, redeemed: false, awarded_at: awarded_at)
end

Rails.logger&.info("Seeded Mr. Damascy: 1 kitchen, #{DeliveryZone.count} zones, " \
                   "#{MenuCategory.count} categories, #{MenuItem.count} items, " \
                   "#{ItemOption.count} options, #{PromoCode.count} promos, #{User.count} users")
