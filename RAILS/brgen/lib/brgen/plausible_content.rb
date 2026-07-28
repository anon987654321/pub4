# frozen_string_literal: true

module Brgen
  # Content pools for the *bulk* of seed data.
  #
  # BergenDemoSeeder already carries hand-curated Bergen content (real places,
  # real neighbourhoods, Norwegian copy) but it only produces a few dozen
  # records. db/seeds.rb then generates hundreds to thousands more from raw
  # Faker, and those were the ones giving the site away: Faker::Lorem Latin in
  # a Norwegian city feed, Faker::Company.name ("Stokes-Bernier") on Bergen
  # shopfronts, Faker::Movie.title on a local TV channel, and — worst — a
  # Faker::Address.city on listings that had Bergen coordinates, so a bike for
  # sale in Bergen claimed to be in "Gailborough".
  #
  # These pools keep the volume but make each record locally plausible. They
  # are deliberately generic within Norwegian city life (no Bergen-only
  # landmarks) so the same pools read correctly for Oslo, Stavanger, Tromsø and
  # the other Norwegian domains in DomainRegistry.
  #
  # Non-Norwegian cities fall back to ENGLISH_* — worse than native copy, but
  # authoring eleven languages of body text is not something a seed file should
  # pretend to do, and English at least parses as language where Lorem did not.
  module PlausibleContent
    # Real Bergen street names, for addresses that should look like addresses.
    # Faker's nb-NO street generator invents plausible-but-fake compounds
    # ("Damroa"); a delivery address in a takeaway demo reads better real.
    BERGEN_STREETS = [
      "Torgallmenningen", "Strandgaten", "Vaskerelven", "Nygårdsgaten",
      "Kong Oscars gate", "Marken", "Håkonsgaten", "Nordnesveien",
      "Øvre Korskirkeallmenningen", "Fjøsangerveien", "Møllendalsveien",
      "Sandviksveien", "Fantoftvegen", "Ibsens gate", "Lars Hilles gate",
      "Christies gate", "Olav Kyrres gate", "Vestre Torggaten",
      "Neumanns gate", "Danmarksplass"
    ].freeze

    BERGEN_BYDELER = %w[
      Sentrum Nordnes Sandviken Kalfaret Møhlenpris Laksevåg
      Fyllingsdalen Fana Årstad Åsane Arna Ytrebygda
    ].freeze

    # --- Posts -------------------------------------------------------------

    # Interpolate %{city} so these work for any Norwegian city domain.
    NORWEGIAN_POST_TITLES = [
      "Noen som vet når Bybanen går igjen?",
      "Beste kaffe i %{city} akkurat nå?",
      "Regnet igjen — tips til innendørs aktiviteter med barn?",
      "Selger sykkel, hvor er det lurt å legge ut?",
      "Nye åpningstider på biblioteket",
      "Anbefalinger til rørlegger i %{city}?",
      "Hvor spiser man best fiskesuppe?",
      "Noen som vil bli med på tur på søndag?",
      "Parkering i sentrum — hva gjør folk egentlig?",
      "Loppemarked til helgen",
      "Er det verdt å ta toget eller bussen til Oslo?",
      "Ledig plass i kollektiv fra 1. neste måned",
      "Hvem har best pris på dekkskifte?",
      "Konsertanbefalinger denne måneden",
      "Tips til turer når det blåser for mye på fjellet",
      "Hvor får man tak i skikkelig godt brød?",
      "Noen erfaring med barnehagene i %{city}?",
      "Bytter bort to konsertbilletter",
      "Hvor kaster man elektronisk avfall?",
      "Beste stedet å jobbe med laptop i %{city}?",
      "Hvem fikser sykkel raskt og billig?",
      "Er det noen som spiller fotball på tirsdager?",
      "Anbefal en tannlege som tar nye pasienter",
      "Hva er egentlig greia med parkeringsappene?",
      "Fant en katt i går — noen som savner den?",
      "Turgruppe for nybegynnere?",
      "Hvor mye betaler folk i strøm nå?",
      "Åpner det noe nytt i sentrum til høsten?",
      "Gode brukthandler i %{city}?",
      "Noen som vet om ledig kontorplass?",
      "Beste badeplass når det først er varmt",
      "Hvordan kommer man seg til flyplassen tidlig morgen?",
      "Tips til bursdagsfeiring for femåring",
      "Er det verdt å bli medlem på treningssenteret?",
      "Noen som har prøvd den nye kaffebaren?",
      "Hvor finner jeg en god frisør?",
      "Savner noen en blå sekk fra bussen?",
      "Hva gjør man en søndag når alt er stengt?",
      "Anbefalinger til bilverksted?"
    ].freeze

    NORWEGIAN_POST_BODIES = [
      "Har prøvd et par steder, men vil gjerne høre hva folk her mener. Trenger ikke være dyrt, bare bra.",
      "Sto en halvtime i går og lurer på om det bare var meg. Noen andre som opplevde det samme?",
      "Ny i byen og prøver å finne ut hvordan ting fungerer her. Alle tips mottas med takk.",
      "Har lest litt rundt men finner ikke noe oppdatert. Håper noen her vet mer.",
      "Vi er to stykker som planlegger, og har plass til noen flere hvis noen vil henge på.",
      "Ikke noe hastverk, men greit å ha på plass før høsten. Sender gjerne detaljer på DM.",
      "Prisene varierer veldig, så jeg prøver å få en peiling før jeg bestemmer meg.",
      "Takk til alle som svarte forrige gang — det hjalp faktisk. Nå har jeg et nytt spørsmål.",
      "Litt usikker på om dette er rett sted å spørre, men prøver likevel.",
      "Har bodd her i noen år nå og oppdager stadig nye steder. Del gjerne deres favoritter."
    ].freeze

    ENGLISH_POST_TITLES = [
      "Anyone know when the trams are running again?",
      "Best coffee in %{city} right now?",
      "Raining again — indoor things to do with kids?",
      "Selling a bike, where's the best place to list it?",
      "New library opening hours",
      "Plumber recommendations in %{city}?",
      "Where do you get the best soup around here?",
      "Anyone want to join a walk on Sunday?",
      "Parking downtown — what do people actually do?",
      "Flea market this weekend"
    ].freeze

    ENGLISH_POST_BODIES = [
      "I've tried a couple of places but would rather hear what people here think. Doesn't need to be fancy, just good.",
      "Waited half an hour yesterday and wondered whether it was just me. Anyone else run into this?",
      "New in town and still working out how things run here. Any tips appreciated.",
      "I've read around a bit but can't find anything current. Hoping someone here knows more.",
      "There are two of us planning it, and there's room for a few more if anyone wants to come along.",
      "No rush, but good to have sorted before autumn. Happy to send details by DM."
    ].freeze

    # --- Marketplace -------------------------------------------------------

    # Norwegian small-business naming patterns, assembled rather than listed so
    # the pool scales to hundreds of stores without visible repetition.
    STORE_PREFIXES = %w[
      Vest Berg Fjord Nord Sør Vestland Bryggen Sentrum Nygård Solheim
      Haukeland Minde Landås Eidsvåg Nesttun Paradis
    ].freeze

    STORE_KINDS = [
      "Elektro", "Møbler", "Sport", "Sykkel", "Foto", "Interiør", "Verksted",
      "Bruktbutikk", "Design", "Antikk", "Bok & Papir", "Hobby", "Musikk",
      "Klær", "Utstyr", "Service"
    ].freeze

    STORE_SUFFIXES = [ "AS", "AS", "AS", "& Sønner", "Handel", "Butikk", "" ].freeze

    # Keyed by the *leaf* category slug db/seeds.rb builds ("<root>-<child>").
    # Keying by root alone put a 55" TV under electronics-audio and winter boots
    # under clothing-outerwear; seeds picks the title first and then files the
    # listing under the matching leaf, so the two can no longer disagree.
    LISTING_TITLES = {
      "electronics-phones" => [
        "iPhone 14, 128 GB — pent brukt", "Samsung Galaxy S23", "iPhone 12, 64 GB",
        "Google Pixel 8, som ny", "Mobildeksel og lader, iPhone"
      ],
      "electronics-computers" => [
        "MacBook Pro 14\" M3", "iPad Air med deksel", "Dell skjerm 27 tommer",
        "Logitech tastatur og mus", "Lenovo ThinkPad T14", "Ekstern harddisk 2 TB"
      ],
      "electronics-audio" => [
        "Sony WH-1000XM5 hodetelefoner", "Bose Soundlink høyttaler",
        "Sonos One, hvit", "Platespiller Audio-Technica", "AirPods Pro, 2. gen"
      ],
      "electronics-gaming" => [
        "PlayStation 5 med to kontrollere", "Nintendo Switch OLED",
        "Xbox Series S", "Gaming-stol, sort/rød", "Steam Deck 512 GB"
      ],
      "clothing-shirts" => [
        "Ullgenser fra Devold", "Skjorte str. L, lite brukt",
        "Collegegenser, str. M", "T-skjorter, pakke med fem"
      ],
      "clothing-trousers" => [
        "Regnbukse til barn, 122 cm", "Turbukse, herre str. 52",
        "Jeans str. 32/32", "Turbukse, dame str. 38"
      ],
      "clothing-shoes" => [
        "Vinterstøvler str. 42", "Ubrukte joggesko str. 40",
        "Fjellstøvler str. 44", "Pensko str. 43, brukt to ganger"
      ],
      "clothing-outerwear" => [
        "Bergans regnjakke str. L", "Norrøna skalljakke, dame M",
        "Helly Hansen seilerjakke", "Dunjakke, brukt én sesong",
        "Vinterjakke til barn, 128 cm"
      ],
      "furniture-sofas" => [
        "Sofa 3-seter, grå", "Hjørnesofa, beige", "Sovesofa, lite brukt",
        "Lenestol, retro"
      ],
      "furniture-tables" => [
        "Spisebord i eik, 6 personer", "Sofabord i glass",
        "Skrivebord med hev/senk", "Kjøkkenbord med to stoler"
      ],
      "furniture-chairs" => [
        "Kontorstol, ergonomisk", "Fire spisestuestoler i teak",
        "Barstoler, to stk", "Barnestol til bord"
      ],
      "furniture-storage" => [
        "IKEA Billy bokhylle", "Kommode med fire skuffer",
        "Garderobeskap, hvitt", "Oppbevaringskasser, seks stk"
      ],
      "vehicles-cars" => [
        "Bilstoler til barn", "Takboks 400 liter", "Snøkjetting, ubrukt",
        "Tilhengerfeste, komplett"
      ],
      "vehicles-bikes" => [
        "Terrengsykkel, 27 gir", "Elsykkel med nytt batteri",
        "Sykkelvogn til barn", "Landeveissykkel str. 54",
        "Barnesykkel 20 tommer"
      ],
      "vehicles-motorcycles" => [
        "Moped, 2019-modell", "Motorsykkelhjelm str. M",
        "Kjøredress, skinn", "Scooter, nylig service"
      ],
      "vehicles-parts" => [
        "Vinterdekk 205/55 R16", "Sykkelstativ for bil",
        "Sommerdekk med felg", "Batterilader til bil"
      ],
      "services-repair" => [
        "Rørlegger — små jobber", "Maler tar oppdrag",
        "Datahjelp for eldre", "Sykkelreparasjon i Sandviken"
      ],
      "services-moving" => [
        "Flyttehjelp med bil", "Bortkjøring av avfall",
        "Hjelp til bæring, to personer"
      ],
      "services-cleaning" => [
        "Vaskehjelp, fast avtale", "Snømåking i Åsane",
        "Hjelp med hage og beskjæring", "Vindusvask, hus og leilighet"
      ],
      "services-tutoring" => [
        "Matematikkundervisning, ungdomsskole", "Fotograf til portrett",
        "Hundepassing i helgene", "Gitartimer for nybegynnere",
        "Norskundervisning, privat"
      ]
    }.freeze

    LISTING_BODIES = [
      "Brukt, men i god stand. Kan hentes i %{bydel}, eventuelt sendes mot frakt.",
      "Selges fordi vi har fått nytt. Fungerer helt som det skal.",
      "Lite brukt og fremdeles pent. Kvittering finnes hvis det er viktig.",
      "Noen bruksmerker som er nevnt over, ellers ingenting å bemerke.",
      "Henting i %{bydel} passer best. Kan møtes i sentrum hvis det er lettere.",
      "Prisen er tenkt som utgangspunkt — gi et bud hvis du er interessert.",
      "Alt originalt utstyr følger med. Røykfritt og dyrefritt hjem."
    ].freeze

    # --- Takeaway ----------------------------------------------------------

    # [name, cuisine] pairs. Names carry no place suffix of their own so that a
    # bydel can be appended as a branch ("Peppes Pizza Laksevåg") once the pool
    # is exhausted. Pairing matters: sampling cuisine independently produced
    # "Curry & Co [Pizza]" and "Ramen Bergen [Mexican]", which is a worse tell
    # than a generic name would have been.
    RESTAURANTS_BY_CUISINE = [
      [ "Pizzabakeren", "Pizza" ],
      [ "Peppes Pizza", "Pizza" ],
      [ "Dolly Dimple's", "Pizza" ],
      [ "Pizzeria Napoli", "Pizza" ],
      [ "Bergen Kebab House", "Kebab" ],
      [ "Kebabhuset", "Kebab" ],
      [ "Døner Ekspress", "Kebab" ],
      [ "Sushi Sentrum", "Japanese" ],
      [ "Sushi & Sake", "Japanese" ],
      [ "Ramen Bergen", "Japanese" ],
      [ "Trattoria Vesta", "Italian" ],
      [ "Pasta Sentralen", "Italian" ],
      [ "Nam Nam Wok", "Chinese" ],
      [ "Kanton Kjøkken", "Chinese" ],
      [ "Curry & Co", "Indian" ],
      [ "Bombay Tandoori", "Indian" ],
      [ "Thai Orkide", "Thai" ],
      [ "Bangkok Bergen", "Thai" ],
      [ "Bergen Burger", "Burger" ],
      [ "Grillhuset", "Burger" ],
      [ "Bare Vestland", "Norwegian" ],
      [ "Fiskeboden", "Norwegian" ],
      [ "Kafé Kippers", "Norwegian" ],
      [ "Bien Snackbar", "Norwegian" ],
      [ "Marken Mat", "Norwegian" ],
      [ "Casa Mexicana", "Mexican" ],
      [ "Taqueria Nordnes", "Mexican" ]
    ].freeze

    DISHES_BY_CUISINE = {
      "Norwegian" => [
        [ "Fiskesuppe", "Kremet suppe med dagens fangst, brød og smør." ],
        [ "Raspeballer", "Serveres med kjøtt, kålrabistappe og smeltet smør." ],
        [ "Laks med potet", "Ovnsbakt laks, kokte poteter og rømmedressing." ],
        [ "Kjøttkaker i brun saus", "Med ertestuing og tyttebær." ],
        [ "Fiskekaker", "Hjemmelagde, med rå løk og flatbrød." ]
      ],
      "Pizza" => [
        [ "Margherita", "Tomat, mozzarella og fersk basilikum." ],
        [ "Pepperoni", "Dobbel pepperoni og ekstra ost." ],
        [ "Vesuvio", "Skinke, ost og oregano." ],
        [ "Kebabpizza", "Kebabkjøtt, løk, jalapeño og hvitløksdressing." ],
        [ "Vegetar", "Paprika, sopp, løk, oliven og squash." ]
      ],
      "Kebab" => [
        [ "Kebab i pita", "Salat, løk, dressing etter ønske." ],
        [ "Kebabtallerken", "Med pommes frites og salat." ],
        [ "Falafelrull", "Vegetar, med hummus og syltet rødløk." ],
        [ "Kyllingwrap", "Grillet kyllingfilet, salat og hvitløksdressing." ]
      ],
      "Burger" => [
        [ "Cheeseburger", "125 g storfe, cheddar, sylteagurk og dressing." ],
        [ "Baconburger", "Med sprøstekt bacon og karamellisert løk." ],
        [ "Vegetarburger", "Bønnebasert, med avokado og chilimajones." ],
        [ "Pommes frites", "Med aioli eller ketchup." ]
      ],
      "Italian" => [
        [ "Pasta carbonara", "Guanciale, egg, pecorino og pepper." ],
        [ "Lasagne", "Langtidskokt kjøttsaus og bechamel." ],
        [ "Risotto med sopp", "Arborio-ris, skogsopp og parmesan." ],
        [ "Tiramisu", "Klassisk, med mascarpone og espresso." ]
      ],
      "Chinese" => [
        [ "Wok med kylling", "Nudler, grønnsaker og østerssaus." ],
        [ "Sursøt svin", "Med ris og paprika." ],
        [ "Vårruller", "Fire stykk, med dipp." ],
        [ "Dumplings", "Dampet, med soya og ingefær." ]
      ],
      "Japanese" => [
        [ "Laksenigiri", "Åtte biter, fersk laks." ],
        [ "California roll", "Krabbe, avokado og agurk." ],
        [ "Ramen med svin", "Tonkotsu-kraft, egg og vårløk." ],
        [ "Edamame", "Dampede soyabønner med havsalt." ]
      ],
      "Indian" => [
        [ "Chicken tikka masala", "Med basmatiris og naan." ],
        [ "Palak paneer", "Spinat og fersk paneer." ],
        [ "Lammekarri", "Mildt krydret, med raita." ],
        [ "Naan med hvitløk", "Bakt i tandoor." ]
      ],
      "Thai" => [
        [ "Pad thai", "Risnudler, tamarind, peanøtter og lime." ],
        [ "Grønn curry", "Kokosmelk, bambus og thaibasilikum." ],
        [ "Tom yum", "Syrlig og sterk suppe med sitrongress." ],
        [ "Mango sticky rice", "Klebrig ris med kokosmelk." ]
      ],
      "Mexican" => [
        [ "Tacos, tre stk", "Mais-tortilla, salsa og koriander." ],
        [ "Burrito", "Ris, bønner, ost og salsa." ],
        [ "Quesadilla", "Ost, kylling og guacamole." ],
        [ "Nachos", "Med jalapeño, ost og rømme." ]
      ]
    }.freeze

    # --- TV ----------------------------------------------------------------

    TV_CHANNEL_NAMES = [
      "Vestland Nyheter", "Bergen Byliv", "Fjordkanalen", "Studio Nordnes",
      "Bybanen TV", "Sport Vest", "Kultur i Vest", "Marken Media",
      "Regnbyen Radio & TV", "Havn og Hav", "Ulriken Live", "Bergen Matglede",
      "Vestkanten Sport", "Nattkanalen", "Studenttv Bergen"
    ].freeze

    TV_VIDEO_TITLES = [
      "Bybanen til Åsane — hva skjer nå?", "Sesongstart på Brann Stadion",
      "Slik lager du fiskesuppe", "Regnrekord i februar",
      "Møt bakeren på Nordnes", "Turtips: Rundemanen på en time",
      "Studentlivet i Bergen", "Fisketorget en tidlig morgen",
      "Konsertsommer i Grieghallen", "Nye sykkelveier i sentrum",
      "Hva koster det å bo i Bergen?", "Vinter på Ulriken",
      "Fem kafeer verdt en omvei", "Havnen døgnet rundt",
      "Kulturnatt — høydepunkter", "Slik pusser du opp gammelt trehus"
    ].freeze

    module_function

    def store_name
      base = "#{STORE_PREFIXES.sample} #{STORE_KINDS.sample}"
      suffix = STORE_SUFFIXES.sample
      suffix.empty? ? base : "#{base} #{suffix}"
    end

    # Pick the product first, and report the leaf category it belongs in, so the
    # caller can file the listing consistently instead of guessing.
    # Returns [title, leaf_category_slug].
    def listing_for(available_leaf_slugs)
      usable = available_leaf_slugs & LISTING_TITLES.keys
      slug = (usable.presence || LISTING_TITLES.keys).sample
      [ LISTING_TITLES.fetch(slug).sample, slug ]
    end

    # [name, cuisine] for the nth seeded restaurant. Cycles the curated pool and
    # opens a "branch" in a bydel once past the end, which is how a real chain
    # would extend rather than inventing a new brand each time.
    def restaurant_for(index)
      name, cuisine = RESTAURANTS_BY_CUISINE[index % RESTAURANTS_BY_CUISINE.size]
      round = index / RESTAURANTS_BY_CUISINE.size
      name = "#{name} #{BERGEN_BYDELER.sample}" unless round.zero?
      [ name, cuisine ]
    end

    def listing_body(bydel: BERGEN_BYDELER.sample)
      format_with(LISTING_BODIES.sample, bydel: bydel)
    end

    def post_title(city_name, norwegian: true)
      pool = norwegian ? NORWEGIAN_POST_TITLES : ENGLISH_POST_TITLES
      format_with(pool.sample, city: city_name)
    end

    def post_body(norwegian: true)
      (norwegian ? NORWEGIAN_POST_BODIES : ENGLISH_POST_BODIES).sample
    end

    def street_address
      "#{BERGEN_STREETS.sample} #{rand(1..98)}"
    end

    def dishes_for(cuisine)
      DISHES_BY_CUISINE[cuisine] || DISHES_BY_CUISINE["Norwegian"]
    end

    def norwegian_country?(country_code)
      country_code.to_s.upcase == "NO"
    end

    # LISTING_TITLES is keyed by root category; seeded categories are slugged
    # "electronics-phones" etc. by db/seeds.rb.
    def root_category(slug)
      slug.to_s.split("-").first
    end

    # Only substitutes the keys a template actually uses, so a template with
    # no placeholders (most of them) passes through untouched rather than
    # raising KeyError on a stray %.
    def format_with(template, **values)
      values.reduce(template) { |acc, (key, value)| acc.gsub("%{#{key}}", value.to_s) }
    end
  end
end
