# frozen_string_literal: true

module Brgen
  module PlausibleContent
    # Store, listing and restaurant pools.
    #
    # Split out for the same reason as Prose: data tables, two thirds of a file
    # whose ceiling is about how much lives in one place.
    module Commerce
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
      ],
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
      [ "Taqueria Nordnes", "Mexican" ],
      ].freeze

      DISHES_BY_CUISINE = {
      "Norwegian" => [
        [ "Fiskesuppe", "Kremet suppe med dagens fangst, brød og smør." ],
        [ "Raspeballer", "Serveres med kjøtt, kålrabistappe og smeltet smør." ],
        [ "Laks med potet", "Ovnsbakt laks, kokte poteter og rømmedressing." ],
        [ "Kjøttkaker i brun saus", "Med ertestuing og tyttebær." ],
        [ "Fiskekaker", "Hjemmelagde, med rå løk og flatbrød." ],
      ],
      "Pizza" => [
        [ "Margherita", "Tomat, mozzarella og fersk basilikum." ],
        [ "Pepperoni", "Dobbel pepperoni og ekstra ost." ],
        [ "Vesuvio", "Skinke, ost og oregano." ],
        [ "Kebabpizza", "Kebabkjøtt, løk, jalapeño og hvitløksdressing." ],
        [ "Vegetar", "Paprika, sopp, løk, oliven og squash." ],
      ],
      "Kebab" => [
        [ "Kebab i pita", "Salat, løk, dressing etter ønske." ],
        [ "Kebabtallerken", "Med pommes frites og salat." ],
        [ "Falafelrull", "Vegetar, med hummus og syltet rødløk." ],
        [ "Kyllingwrap", "Grillet kyllingfilet, salat og hvitløksdressing." ],
      ],
      "Burger" => [
        [ "Cheeseburger", "125 g storfe, cheddar, sylteagurk og dressing." ],
        [ "Baconburger", "Med sprøstekt bacon og karamellisert løk." ],
        [ "Vegetarburger", "Bønnebasert, med avokado og chilimajones." ],
        [ "Pommes frites", "Med aioli eller ketchup." ],
      ],
      "Italian" => [
        [ "Pasta carbonara", "Guanciale, egg, pecorino og pepper." ],
        [ "Lasagne", "Langtidskokt kjøttsaus og bechamel." ],
        [ "Risotto med sopp", "Arborio-ris, skogsopp og parmesan." ],
        [ "Tiramisu", "Klassisk, med mascarpone og espresso." ],
      ],
      "Chinese" => [
        [ "Wok med kylling", "Nudler, grønnsaker og østerssaus." ],
        [ "Sursøt svin", "Med ris og paprika." ],
        [ "Vårruller", "Fire stykk, med dipp." ],
        [ "Dumplings", "Dampet, med soya og ingefær." ],
      ],
      "Japanese" => [
        [ "Laksenigiri", "Åtte biter, fersk laks." ],
        [ "California roll", "Krabbe, avokado og agurk." ],
        [ "Ramen med svin", "Tonkotsu-kraft, egg og vårløk." ],
        [ "Edamame", "Dampede soyabønner med havsalt." ],
      ],
      "Indian" => [
        [ "Chicken tikka masala", "Med basmatiris og naan." ],
        [ "Palak paneer", "Spinat og fersk paneer." ],
        [ "Lammekarri", "Mildt krydret, med raita." ],
        [ "Naan med hvitløk", "Bakt i tandoor." ],
      ],
      "Thai" => [
        [ "Pad thai", "Risnudler, tamarind, peanøtter og lime." ],
        [ "Grønn curry", "Kokosmelk, bambus og thaibasilikum." ],
        [ "Tom yum", "Syrlig og sterk suppe med sitrongress." ],
        [ "Mango sticky rice", "Klebrig ris med kokosmelk." ],
      ],
      "Mexican" => [
        [ "Tacos, tre stk", "Mais-tortilla, salsa og koriander." ],
        [ "Burrito", "Ris, bønner, ost og salsa." ],
        [ "Quesadilla", "Ost, kylling og guacamole." ],
        [ "Nachos", "Med jalapeño, ost og rømme." ],
      ],
      }.freeze
    end
  end
end
