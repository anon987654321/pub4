# frozen_string_literal: true

module Brgen
  # Every literal Bergen has in the demo seed: the people, the posts, the
  # listings, the bios, the neighbourhoods, the places, the restaurants, the
  # channels and the Live notes.
  #
  # It sat inside BergenDemoSeeder, where five hundred lines of data made an
  # eight-hundred-line god class out of a class with two public methods. The
  # seeder never breached on method count; it breached on length, and the
  # length was this. Splitting the seeder by responsibility would have been the
  # wrong cut: a data file and the code that reads it are two things, and only
  # one of them is code.
  #
  # Included rather than referenced, so every name reads inside the seeder
  # exactly as it did before and constant lookup goes through the ancestor
  # chain — BergenDemoSeeder::LIVE_NOTES still resolves, which is what the
  # seeder's own test asks for.
  module BergenDemoData
    RADIO_BERGEN_PLAYLIST = "Radio Bergen"

    USERS = [
      %w[Emilie emilie_floyen],
      %w[Henrik henrik_vestland],
      %w[Kari kari_bybanen],
      %w[Ola ola_nordnes],
      %w[Ingrid ingrid_ulriken],
      %w[Magnus magnus_student],
      %w[Sofie sofie_regnby],
      %w[Anders anders_fisketorget],
      %w[Marte marte_kode24],
      %w[Jonas jonas_7fjell],
      %w[Hanne hanne_sandviken],
      %w[Per per_laksevag],
      %w[Silje silje_korall],
      %w[Torbjørn tor_fana],
      %w[Live live_bergenlive]
    ].freeze

    FEATURED_POSTS = BergenDemoFeaturedPosts::FEATURED_POSTS
    POSTS = BergenDemoPosts::POSTS

    LISTINGS = [
      { user: "anders_fisketorget", title: "Brukt sykkel — Bergen sentrum", price_cents: 3_500_00, image: "bergen-bike-sale" },
      { user: "marte_kode24", title: "MacBook Air M1, pent brukt", price_cents: 6_500_00, image: "bergen-macbook" },
      { user: "tor_fana", title: "IKEA sofa, hentes Fana", price_cents: 2_000_00, image: "bergen-sofa" },
      { user: "hanne_sandviken", title: "Barnevogn, god stand", price_cents: 1_800_00, image: "bergen-stroller" },
      { user: "per_laksevag", title: "Telemarkski + støvler", price_cents: 2_400_00, image: "bergen-skis" }
    ].freeze

    DATING_BIOS = [
      {
        user: "emilie_floyen", gender: "woman", looking_for: "man", age: 28, bydel: "Nordnes",
        bio: "Redaktør, Fløyen før frokost, og altfor mange bøker. Leter etter noen som tåler regn og har meninger om kaffe.",
        image: "bergen-dating-emilie"
      },
      {
        user: "magnus_student", gender: "man", looking_for: "woman", age: 24, bydel: "Møhlenpris",
        bio: "UiB psykologi, spiller gitar dårlig men med god energi. Første date: reker på Torget eller kort tur på Rundemanen.",
        image: "bergen-dating-magnus"
      },
      {
        user: "silje_korall", gender: "woman", looking_for: "everyone", age: 31, bydel: "Sandviken",
        bio: "Designer, Bergenfest-entusiast og sjef over Spotify-listen i kollektivet. Bonuspoeng for folk som faktisk møter opp.",
        image: "bergen-dating-silje"
      },
      {
        user: "jonas_7fjell", gender: "man", looking_for: "woman", age: 33, bydel: "Kalfaret",
        bio: "Løper stier, lager middag hjemme, savner sol fra Østlandet men ikke bergenshumoren. Vil gjerne finne noen til 7-fjell og taco.",
        image: "bergen-dating-jonas"
      },
      {
        user: "henrik_vestland", gender: "man", looking_for: "woman", age: 30, bydel: "Nordnes",
        bio: "Maritim ingeniør, seiler når det ikke øser, og har sterke meninger om fiskesuppe. Søker rolig match med litt edge.",
        image: "bergen-dating-henrik"
      },
      {
        user: "ingrid_ulriken", gender: "woman", looking_for: "man", age: 26, bydel: "Laksevåg",
        bio: "Sykepleier, alltid med ekstra lag i sekken. Elsker Ulriken, dårlig på å svare på DM men god til å møtes i virkeligheten.",
        image: "bergen-dating-ingrid"
      },
      {
        user: "sofie_regnby", gender: "woman", looking_for: "man", age: 29, bydel: "Fyllingsdalen",
        bio: "Jobber i kultur, går mye på konsert og lite på klubb. Vil ha noen som tåler både Grieghallen og fredagspizza.",
        image: "bergen-dating-sofie"
      },
      {
        user: "anders_fisketorget", gender: "man", looking_for: "woman", age: 35, bydel: "Sentrum",
        bio: "Kokk, tidlig oppe, sent hjem. Har barn annenhver uke så planlegging er sexy. Matlagerskills inkludert i pakken.",
        image: "bergen-dating-anders"
      },
      {
        user: "hanne_sandviken", gender: "woman", looking_for: "man", age: 32, bydel: "Sandviken",
        bio: "Lærer, nylig separert men klar for nye starter. Barn i bildet — hvis du ikke digger det er vi ulike.",
        image: "bergen-dating-hanne"
      },
      {
        user: "per_laksevag", gender: "man", looking_for: "woman", age: 37, bydel: "Laksevåg",
        bio: "Elektriker, hytte i Hardanger når jeg får fri. Liker direkte kommunikasjon, dårlig på småprat men god på praktiske ting.",
        image: "bergen-dating-per"
      },
      {
        user: "live_bergenlive", gender: "woman", looking_for: "everyone", age: 27, bydel: "Sentrum",
        bio: "Booking og konsert, kjenner halve byen men vil gjerne kjenne én skikkelig. Radio Bergen er min guilty pleasure.",
        image: "bergen-dating-live"
      },
      {
        user: "marte_kode24", gender: "woman", looking_for: "man", age: 25, bydel: "Fana",
        bio: "Utvikler på Mesh, nerd for kart og offentlig transport. Swipe høyre hvis du kan forklare Bybanen uten å bli sur.",
        image: "bergen-dating-marte"
      }
    ].freeze

    DATING_MUTUAL_PAIRS = [
      %w[emilie_floyen magnus_student],
      %w[silje_korall jonas_7fjell],
      %w[henrik_vestland ingrid_ulriken],
      %w[hanne_sandviken per_laksevag]
    ].freeze

    DATING_ONE_WAY_LIKES = [
      %w[sofie_regnby anders_fisketorget],
      %w[marte_kode24 live_bergenlive]
    ].freeze

    NEIGHBORHOODS = [
      [ "Sentrum", "sentrum" ],
      [ "Nordnes", "nordnes" ],
      [ "Sandviken", "sandviken" ],
      [ "Kalfaret", "kalfaret" ],
      [ "Møhlenpris", "mohlenpris" ],
      [ "Laksevåg", "laksevag" ],
      [ "Fyllingsdalen", "fyllingsdalen" ],
      [ "Fana", "fana" ]
    ].freeze

    PLACES = [
      { slug: "floybanen", name: "Fløibanen", kind: "attraction", neighborhood: "sentrum",
        latitude: 60.3963, longitude: 5.3284, address: "Vetrlidsallmenningen 23", image: "bergen-place-floybanen" },
      { slug: "bryggen", name: "Bryggen", kind: "attraction", neighborhood: "sentrum",
        latitude: 60.3974, longitude: 5.3244, address: "Bryggen", image: "bergen-place-bryggen" },
      { slug: "fisketorget", name: "Fisketorget", kind: "market", neighborhood: "sentrum",
        latitude: 60.3945, longitude: 5.3251, address: "Torget", image: "bergen-place-fisketorget" },
      { slug: "grieghallen", name: "Grieghallen", kind: "venue", neighborhood: "sentrum",
        latitude: 60.3892, longitude: 5.3293, address: "Edvard Griegs plass 1", image: "bergen-place-grieghallen" },
      { slug: "ulriken", name: "Ulriken", kind: "trail", neighborhood: "kalfaret",
        latitude: 60.3721, longitude: 5.3512, address: "Ulriken 640", image: "bergen-place-ulriken" },
      { slug: "lungegaardsvann", name: "Store Lungegårdsvann", kind: "park", neighborhood: "sentrum",
        latitude: 60.3896, longitude: 5.3362, address: "Lungegårdsvannet", image: "bergen-place-lungegaardsvann" },
      { slug: "nordnesparken", name: "Nordnesparken", kind: "park", neighborhood: "nordnes",
        latitude: 60.3998, longitude: 5.3078, address: "Nordnes", image: "bergen-place-nordnesparken" },
      { slug: "vilvite", name: "VilVite", kind: "museum", neighborhood: "sentrum",
        latitude: 60.3814, longitude: 5.3321, address: "Thormøhlens check 51", image: "bergen-place-vilvite" }
    ].freeze

    RESTAURANTS = [
      {
        user: "ola_nordnes", name: "Colonialen", cuisine_type: "Norwegian",
        address: "Nordnes 33", neighborhood: "nordnes",
        latitude: 60.3991, longitude: 5.3082,
        delivery_fee_cents: 4_900, min_order_cents: 15_000, rating: 4.6,
        menu: [
          { name: "Eggerøre med spekeskinke", description: "Søndagsbrunch-klassiker fra Nordnes.", price_cents: 16_500, image: "bergen-brunch" },
          { name: "Kanelbolle", description: "Bakt samme morgen — best med kaffe.", price_cents: 4_500, image: "bergen-bakery" },
          { name: "Fiskesuppe", description: "Dagens fangst, brød og smør.", price_cents: 18_900, image: "bergen-takeaway-fiskesuppe" }
        ]
      },
      {
        user: "anders_fisketorget", name: "Fish Me", cuisine_type: "Norwegian",
        address: "Zachariasbryggen 6", neighborhood: "sentrum",
        latitude: 60.3948, longitude: 5.3249,
        delivery_fee_cents: 5_900, min_order_cents: 18_000, rating: 4.8,
        menu: [
          { name: "Reker på briks", description: "Ferske reker med sitron og aioli.", price_cents: 22_900, image: "bergen-takeaway-fishme" },
          { name: "Blåskjell i hvitvin", description: "Løk, persille og brød.", price_cents: 19_500, image: "bergen-takeaway-blaskjell" },
          { name: "Fisk og chips", description: "Torsk, remoulade og pommes.", price_cents: 17_500, image: "bergen-takeaway-fisk-og-chips" }
        ]
      },
      {
        user: "henrik_vestland", name: "Potetkjelleren", cuisine_type: "Pizza",
        address: "Kong Oscars gate 1A", neighborhood: "sentrum",
        latitude: 60.3936, longitude: 5.3258,
        delivery_fee_cents: 3_900, min_order_cents: 12_000, rating: 4.4,
        menu: [
          { name: "Margherita", description: "San Marzano, fior di latte, basilikum.", price_cents: 14_900, image: "bergen-takeaway-potetkjelleren" },
          { name: "Pepperoni", description: "Klassisk, litt chili.", price_cents: 16_500, image: "bergen-takeaway-pepperoni" },
          { name: "Quattro formaggi", description: "Fire oster, hvitløkolje.", price_cents: 17_900, image: "bergen-takeaway-quattro-formaggi" }
        ]
      },
      {
        user: "sofie_regnby", name: "Dyvekes", cuisine_type: "Norwegian",
        address: "Øvre Fossgård 1", neighborhood: "sentrum",
        latitude: 60.3968, longitude: 5.3271,
        delivery_fee_cents: 5_500, min_order_cents: 20_000, rating: 4.7,
        menu: [
          { name: "Bergensk fiskesuppe", description: "Kremet, med reker og pynt.", price_cents: 21_500, image: "bergen-takeaway-dyvekes" },
          { name: "Pinnekjøtt", description: "Sesong — bestill i god tid.", price_cents: 24_900, image: "bergen-takeaway-pinnekjott" },
          { name: "Rømmegrøt", description: "Med sukker og kanel.", price_cents: 9_900, image: "bergen-takeaway-colonialen" }
        ]
      }
    ].freeze

    TV_CHANNELS = [
      {
        user: "live_bergenlive", name: "Bergen Live", slug: "bergen-live",
        description: "Konsert, klubb og nattbuss — direkte fra sentrum.",
        avatar: "bergen-tv-live-avatar", banner: "bergen-tv-live-banner",
        videos: [
          { title: "Open mic på Logen — høydepunkter", thumbnail: "bergen-logen", duration_seconds: 248, views_count: 1_240 },
          { title: "Radio Bergen nattbuss mix", thumbnail: "bergen-radio-night", duration_seconds: 312, views_count: 890 }
        ]
      },
      {
        user: "sofie_regnby", name: "Bergen Kultur", slug: "bergen-kultur",
        description: "Grieghallen, teater og byens kulturkalender.",
        avatar: "bergen-tv-kultur-avatar", banner: "bergen-tv-kultur-banner",
        videos: [
          { title: "Bak scenen: Bergen Filharmoniske", thumbnail: "bergen-concert-hall", duration_seconds: 420, views_count: 2_100 },
          { title: "Pepperkakebyen — familietips", thumbnail: "bergen-pepperkakebyen", duration_seconds: 185, views_count: 3_400 }
        ]
      },
      {
        user: "kari_bybanen", name: "Bybanen Bergen", slug: "bybanen-bergen",
        description: "Linjekart, forsinkelser og reisetips for Skyss.",
        avatar: "bergen-tv-bybanen-avatar", banner: "bergen-lungegaardsvann",
        videos: [
          { title: "Florida → Byparken på 4 min", thumbnail: "bergen-lungegaardsvann", duration_seconds: 96, views_count: 5_600 },
          { title: "Regnvær og bybane — vinterdrift", thumbnail: "bergen-bryggen-rain", duration_seconds: 210, views_count: 1_780 }
        ]
      }
    ].freeze

    # Jodel-shaped Live notes: short, anonymous, geo-stamped for /live demo density.
    LIVE_NOTES = [
      { hours_ago: 0.5, body: "Noen som har sett røyk over Damsgård? Eller bare tåke?" },
      { hours_ago: 1, body: "Ledig sitteplass på bybanen mot Fyllingsdalen, vogn 2." },
      { hours_ago: 2, body: "Gratis kaffe på uteservering ved Torget — ta med egen kopp." },
      { hours_ago: 3, body: "Hunden min rømte ved Nordnesparken, brun terrier, svarer på Pip." },
      { hours_ago: 4, body: "Pepperkakebyen-kø er kort akkurat nå (hverdag 14:00)." },
      { hours_ago: 5, body: "Noen som trenger et paraplylån på Bryggen? Har en ekstra." },
      { hours_ago: 8, body: "Stille på Fløyen i kveld — nesten ingen turister." },
      { hours_ago: 12, body: "Lydsjekk: er det konsert på Logen i kveld eller bare øving?" },
      { hours_ago: 18, body: "Fisketorget lukter skikkelig godt. Anbefaler reker." },
      { hours_ago: 24, body: "Regnværsdag: beste bibliotekkroken er 2. etasje, vindu mot dammen." }
    ].freeze
  end
end
