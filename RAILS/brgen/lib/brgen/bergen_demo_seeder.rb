# frozen_string_literal: true

require "yaml"

module Brgen
  # Realistic Bergen / r/bergen-inspired demo content for brgen.no (Tradedoubler, demos).
  # Norwegian copy, local handles, staggered timestamps, optional picsum + postpro attachments.
  class BergenDemoSeeder
    RADIO_BERGEN_PLAYLIST = "Radio Bergen"
    LOCAL_AUDIO_BASE = ENV.fetch("RADIO_BERGEN_AUDIO_BASE", "https://ai.brgen.no")

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

    POSTS = [  # Curated for realism; in full seed use SEED_SCALE for volume + Faker for "millions" feel via counters (e.g. 10k+ views)
      {
        user: "emilie_floyen", community: "bergen", hours_ago: 1, votes: 14,
        title: "Hva skjer i Bergen i helgen?",
        content: "Fredag: standup på Logen, lørdag Pepperkakebyen med nevøen, søndag kanskje tur på Damsgårdsfjellet. Hva er deres planer — og er det noe jeg bommer på?",
        comments: [
          "VilVite har familiedag lørdag, verdt en tur.",
          "Kolonialen brunch søndag hvis dere vil ha rolig start."
        ]
      },
      {
        user: "live_bergenlive", community: "musikk", hours_ago: 2, votes: 12,
        title: "Radio Bergen-playlisten er oppe — hvem lager neste?",
        content: "Har lagt inn AKMD-lokallåter og beat-referanser fra manifestet vårt. Perfekt til nattbuss hjem fra sentrum. Legg gjerne inn egne funn i kommentarene.",
        image: "bergen-radio-night", comments: [
          "Elsker Sandviken Hotell B — instant nostalgi.",
          "Kan noen lage en ren AKMD-only variant?"
        ]
      },
      {
        user: "emilie_floyen", community: "bergen", hours_ago: 3, votes: 11,
        title: "Sol på Fløyen — verdt hele turen",
        content: "Tok Fløibanen opp før jobb. Utsikten over Vågen var helt vill i morgensola. Anbefaler å komme før kl 09 hvis dere vil unngå kø.",
        image: "bergen-floyen-morning", comments: [
          "Var der i går! Magisk.",
          "Husk varm jakke på toppen, blåser alltid."
        ]
      },
      {
        user: "henrik_vestland", community: "bergen", hours_ago: 5, votes: 9,
        title: "Regnværsdag på Bryggen",
        content: "Sitter på Kaffebrenneriet og hører regnet mot taket. Hvor er favorittstedet deres når det øser ned?",
        image: "bergen-bryggen-rain", comments: [
          "Dampen på Torget, alltid.",
          "Biblioteket + kaffe fra Godt Brød."
        ]
      },
      {
        user: "kari_bybanen", community: "norge", hours_ago: 6, votes: 10,
        title: "Bybanen forsinket igjen?",
        content: "Står på Florida og det kommer ingen avgang mot sentrum. Noen som vet om det er signalfeil?",
        comments: [
          "Ja, meldt på Skyss-appen nå.",
          "Ta buss 12 som backup hvis du har det travelt."
        ]
      },
      {
        user: "marte_kode24", community: "bergen", hours_ago: 7, votes: 8,
        title: "Dating i Bergen — ghosting eller bare regn?",
        content: "Tredje match denne uka som foreslår kaffe på Møhlenpris og så forsvinner. Er dette en bygreie, eller bare meg?",
        comments: [
          "Regn + travel hverdag, folk prioriterer om.",
          "Prøv aktiv date — Fløyen eller VilVite, mindre press."
        ]
      },
      {
        user: "ola_nordnes", community: "mat", hours_ago: 9, votes: 7,
        title: "Beste kanelbolle i sentrum?",
        content: "Jeg sverger til Baker Hansen, men kollegaen mener Godt Brød er bedre. Hva stemmer folket for?",
        image: "bergen-bakery", comments: [
          "Baker Hansen når de er ferske.",
          "Colonialen på Nordnes er undervurdert."
        ]
      },
      {
        user: "ingrid_ulriken", community: "bergen", hours_ago: 10, votes: 8,
        title: "Pepperkakebyen — tips før første gang?",
        content: "Skal dit med søster og to barn (6 og 9). Hva bør vi forhåndsbooke, og når er det minst kø?",
        image: "bergen-pepperkakebyen", comments: [
          "Tidlig ettermiddag på hverdag er best.",
          "Ta med termos, køen ved karrusellen kan bli lang."
        ]
      },
      {
        user: "ingrid_ulriken", community: "bergen", hours_ago: 14, votes: 6,
        title: "Ulriken i kveld — hvem blir med?",
        content: "Planlegger tur opp Ulriken rundt 18. Rolig tempo, kanskje mat på toppen. DM om du vil henge.",
        image: "bergen-ulriken-trail", comments: [
          "Er med! Har ekstra hodelykt.",
          "Sjekk værmeldingen først, skyer ruller inn fort."
        ]
      },
      {
        user: "magnus_student", community: "bergen", hours_ago: 16, votes: 7,
        title: "UiB-eksamen og ingen plass på biblioteket",
        content: "Alle plassene på HF-bib er borte. Tips til stille leseplasser i sentrum etter kl 16?",
        comments: [
          "Studentersamfundet, øverste etasje.",
          "KODE café hvis du tåler litt bakgrunnsstøy."
        ]
      },
      {
        user: "sofie_regnby", community: "kultur", hours_ago: 18, votes: 6,
        title: "Grieghallen i helgen",
        content: "Skal på Beethoven med Bergen Filharmoniske. Har noen vært der nylig — hvor tidlig bør man være inne?",
        image: "bergen-concert-hall", comments: [
          "30 min før er plenty.",
          "Husk at garderoben kan ta tid på fulle dager."
        ]
      },
      {
        user: "anders_fisketorget", community: "mat", hours_ago: 20, votes: 5,
        title: "Fisketorget lørdag — hva kjøper dere?",
        content: "Reker, blåskjell og litt laks hver gang. Finnes det noe lokalt jeg alltid overser?",
        image: "bergen-fish-market", comments: [
          "Kveite om de har det.",
          "Spør om hummersuppe-restene, billig og godt."
        ]
      },
      {
        user: "marte_kode24", community: "bergen", hours_ago: 22, votes: 6,
        title: "Tech-meetup på Mesh?",
        content: "Så at det er meetup på Mesh neste uke. Noen her som har vært — er det mer mingling eller foredrag?",
        comments: [
          "Begge deler, avslappet stemning.",
          "Ta med ladekabel, sitteplassene fylles fort."
        ]
      },
      {
        user: "jonas_7fjell", community: "bergen", hours_ago: 24, votes: 7,
        title: "Damsgårdsfjellet ved solnedgang",
        content: "Løp opp i går kveld — helt rått lys over Puddefjorden. Lokal hemmelighet eller kjenner alle til dette allerede?",
        image: "bergen-damsgardsfjellet", comments: [
          "Kjenner mange til det, men fortjener mer love.",
          "Ta vindjakke, det blåser som regel på toppen."
        ]
      },
      {
        user: "jonas_7fjell", community: "bergen", hours_ago: 36, votes: 5,
        title: "Løypeforslag for 7-fjellsturen",
        content: "Skal endelig ta 7-fjellsturen i sommer. Vil gjerne dele etappen i to dager — har dere en favorittrute?",
        image: "bergen-hiking", comments: [
          "Dag 1: Fløyen–Rundemanen, dag 2: resten.",
          "Husk nok vann mellom Lyderhorn og Damsgårdsfjellet."
        ]
      },
      {
        user: "hanne_sandviken", community: "norge", hours_ago: 38, votes: 5,
        title: "Barnehageplass i Bergen — realistisk ventetid?",
        content: "Flytter til Sandviken til høsten. Hva er erfaringen deres med ventelister i bydelen?",
        comments: [
          "Var 4 måneder for oss, avhengig av bydel.",
          "Søk tidlig og følg opp med kommunen."
        ]
      },
      {
        user: "per_laksevag", community: "bergen", hours_ago: 40, votes: 6,
        title: "Nye sykkelstier langs Store Lungegårdsvann",
        content: "Syklet rundt vannet i går kveld. Nye lys gjør det mye tryggere. Håper de fortsetter mot Puddefjorden.",
        image: "bergen-lungegaardsvann", comments: [
          "Enig, stor forbedring.",
          "Fortsatt litt glatt ved regn, ta det rolig i svingene."
        ]
      },
      {
        user: "silje_korall", community: "musikk", hours_ago: 44, votes: 8,
        title: "Bergenfest — hvilke artister satser dere på?",
        content: "Lineup er ute og jeg klarer ikke velge én dag. Hvem er must-see i år?",
        comments: [
          "Fredagskvelden ser sterk ut.",
          "Kom tidlig for parken, det blir folksomt."
        ]
      },
      {
        user: "tor_fana", community: "bergen", hours_ago: 48, votes: 4,
        title: "Vannlekkasje i leilighet — hva gjør man først?",
        content: "Vann fra taket i Fana i natt. Har dokumentert og ringt utleier. Noe mer jeg bør gjøre med en gang?",
        comments: [
          "Ta bilder av alt, også inventar.",
          "Meld til forsikring samme dag."
        ]
      },
      {
        user: "live_bergenlive", community: "kultur", hours_ago: 52, votes: 5,
        title: "Standup på Logen denne uken",
        content: "Noen som har vært på open mic der? Tenker å teste en kort settliste.",
        image: "bergen-logen", comments: [
          "Hyggelig publikum, kom tidlig.",
          "Book plass, det er begrenset kapasitet."
        ]
      },
      {
        user: "ola_nordnes", community: "mat", hours_ago: 56, votes: 6,
        title: "Kolonialen brunch — verdt prisen?",
        content: "Vurderer å ta med foreldre dit søndag. Er porsjonene og stemningen like gode som folk sier?",
        image: "bergen-brunch", comments: [
          "Ja, book bord i god tid.",
          "Sitte ute hvis været spiller på lag."
        ]
      },
      {
        user: "emilie_floyen", community: "bergen", hours_ago: 72, votes: 5, anonymous: true,
        title: "Anonym: nattbuss etter sentrum?",
        content: "Jobber sent på hverdager. Er nattbussene fortsatt upålitelige etter midnatt, eller har det blitt bedre?",
        comments: [
          "Bedre etter ruteendring, men sjekk Boreal-app.",
          "Skyss natt viser sanntid nå."
        ]
      },
      {
        user: "henrik_vestland", community: "mat", hours_ago: 88, votes: 4,
        title: "Pizza på Nordnes — Deli eller Bella?",
        content: "Klassisk fredagskrangel i kollektivet. Hva vinner i Bergen akkurat nå?",
        comments: [
          "Deli for tynn bunn.",
          "Bella når man vil ha storfamilie-porsjoner."
        ]
      },
      {
        user: "kari_bybanen", community: "bergen", hours_ago: 96, votes: 7,
        title: "Tåk over Vågen i dag",
        content: "Gikk over Bryggen i tjukk tåke — føltes som en annen by. Tok noen bilder hvis noen vil ha wallpaper.",
        image: "bergen-fog-vagen", comments: [
          "Legg ut!",
          "Perfekt stemning for svart/hvitt."
        ]
      },
      {
        user: "ola_nordnes", community: "norge", hours_ago: 120, votes: 5,
        title: "Boligpriser i Bergen — fortsatt helt sprøtt?",
        content: "Ser på 2-roms i Møhlenpris. Er det noen som faktisk har kjøpt nylig uten å vinne arv-lotteriet?",
        comments: [
          "Møhlenpris holder seg høyt, sjekk borettslag vs. eier.",
          "Vurder Laksevåg hvis du vil ha bedre kvm-pris."
        ]
      },
      {
        user: "ingrid_ulriken", community: "bergen", hours_ago: 140, votes: 4,
        title: "Hundepark anbefalinger?",
        content: "Ny hund i familien. Hvor i Bergen er det best å slippe den løs uten å måtte kjøre 40 min?",
        image: "bergen-dog-park", comments: [
          "Nordnesparken tidlig morgen.",
          "Fana fjellstier hvis den tåler mer aktivitet."
        ]
      },
      {
        user: "sofie_regnby", community: "bergen", hours_ago: 28, votes: 6,
        title: "VilVite med barn — hva er best?",
        content: "Søndagstur med seksåring. Er det noen utstillinger eller show dere alltid prioriterer?",
        comments: [
          "Vitenshowet er gull verdt.",
          "Ta med lunsj, kaféa kan bli full."
        ]
      },
      {
        user: "anders_fisketorget", community: "bergen", hours_ago: 32, votes: 5,
        title: "Studentersamfundet torsdag — hvem møter?",
        content: "Tenker å dra dit etter jobb for billig øl og quiz. Er det fortsatt god stemning midt i uka?",
        comments: [
          "Quiz starter kl 19, kom tidlig.",
          "Bordene ved vinduet går først."
        ]
      },
      {
        user: "tor_fana", community: "bergen", hours_ago: 4, votes: 21,
        title: "Brann på Stadion i kveld — hvor ser dere kampen?",
        content: "Fikk ikke billett og vil ikke se den alene. Hvilken pub tar imot Brann-folk uten kø?",
        comments: [
          "Fotballpuben i Nygårdsgaten. Kom en time før avspark.",
          "Bien på Møhlenpris viser alltid, og trykket er høyt."
        ]
      },
      {
        user: "hanne_sandviken", community: "bergen", hours_ago: 12, votes: 18,
        title: "Leiepriser i Bergen — har de flatet ut?",
        content: "Leter etter toroms under 14 000 nær sentrum. Urealistisk i år, eller finnes det fortsatt?",
        comments: [
          "Let ett stopp ut på Bybanen. Prisen faller fort.",
          "Følg Hybel og Finn daglig. De gode går på timer."
        ]
      },
      {
        user: "magnus_student", community: "bergen", hours_ago: 30, votes: 15,
        title: "Flyttet til Bergen forrige uke — hva bør jeg vite?",
        content: "Ny jobb, kjenner ingen. Gi meg det ene rådet dere skulle hatt første måneden her.",
        comments: [
          "Kjøp ordentlig regntøy før du kjøper noe annet.",
          "Bli med på en fjelltur. Det er slik folk finner venner her."
        ]
      },
      {
        user: "henrik_vestland", community: "bergen", hours_ago: 15, votes: 24,
        title: "Dag 18 med regn — teller noen fortsatt?",
        content: "Naboen sier det er sunt. Jeg sier vi bygger ark. Hvordan holder dere humøret oppe i grå uker?",
        comments: [
          "Paraply er for nybegynnere. Skikkelig jakke og godt humør.",
          "Kaffe, bok, vindu mot Vågen. Da blir regnet kulisse."
        ]
      }
    ].freeze

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
        latitude: 60.3814, longitude: 5.3321, address: "Thormøhlens gate 51", image: "bergen-place-vilvite" }
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
          { name: "Fiskesuppe", description: "Dagens fangst, brød og smør.", price_cents: 18_900, image: "bergen-fish-market" }
        ]
      },
      {
        user: "anders_fisketorget", name: "Fish Me", cuisine_type: "Norwegian",
        address: "Zachariasbryggen 6", neighborhood: "sentrum",
        latitude: 60.3948, longitude: 5.3249,
        delivery_fee_cents: 5_900, min_order_cents: 18_000, rating: 4.8,
        menu: [
          { name: "Reker på briks", description: "Ferske reker med sitron og aioli.", price_cents: 22_900, image: "bergen-takeaway-fishme" },
          { name: "Blåskjell i hvitvin", description: "Løk, persille og brød.", price_cents: 19_500, image: "bergen-fish-market" },
          { name: "Fisk og chips", description: "Torsk, remoulade og pommes.", price_cents: 17_500, image: "bergen-takeaway-fishme" }
        ]
      },
      {
        user: "henrik_vestland", name: "Potetkjelleren", cuisine_type: "Pizza",
        address: "Kong Oscars gate 1A", neighborhood: "sentrum",
        latitude: 60.3936, longitude: 5.3258,
        delivery_fee_cents: 3_900, min_order_cents: 12_000, rating: 4.4,
        menu: [
          { name: "Margherita", description: "San Marzano, fior di latte, basilikum.", price_cents: 14_900, image: "bergen-takeaway-potetkjelleren" },
          { name: "Pepperoni", description: "Klassisk, litt chili.", price_cents: 16_500, image: "bergen-takeaway-potetkjelleren" },
          { name: "Quattro formaggi", description: "Fire oster, hvitløkolje.", price_cents: 17_900, image: "bergen-takeaway-potetkjelleren" }
        ]
      },
      {
        user: "sofie_regnby", name: "Dyvekes", cuisine_type: "Norwegian",
        address: "Øvre Fossgård 1", neighborhood: "sentrum",
        latitude: 60.3968, longitude: 5.3271,
        delivery_fee_cents: 5_500, min_order_cents: 20_000, rating: 4.7,
        menu: [
          { name: "Bergensk fiskesuppe", description: "Kremet, med reker og pynt.", price_cents: 21_500, image: "bergen-takeaway-dyvekes" },
          { name: "Pinnekjøtt", description: "Sesong — bestill i god tid.", price_cents: 24_900, image: "bergen-takeaway-dyvekes" },
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

    def initialize(city, attach_media: !DemoMedia.skip_attach?)
      @city = city
      @attach_media = attach_media
      @users_by_username = {}
    end

    def seed!
      ActsAsTenant.with_tenant(@city) do
        neighborhoods = ensure_neighborhoods
        communities = ensure_communities
        seed_users
        seed_posts(communities)
        seed_listings
        seed_live_posts
        seed_playlists
        seed_dating
        seed_dating_likes
        seed_places(neighborhoods)
        seed_takeaway
        seed_tv
      end
    end

    private

    def ensure_neighborhoods
      NEIGHBORHOODS.index_with do |name, slug|
        Neighborhood.find_or_create_by!(city: @city, slug: slug) { |row| row.name = name }
      end
    end

    def ensure_communities
      # Admin may pre-exist outside this tenant scope (username "admin" vs "admin_<slug>").
      admin = ActsAsTenant.without_tenant do
        User.strict_loading(false).find_by(email_address: "admin@#{@city.domain}") ||
          User.strict_loading(false).find_by(username: "admin_#{@city.slug}") ||
          User.strict_loading(false).find_by(username: "admin", city_id: @city.id) ||
          User.strict_loading(false).find_by(username: "admin") ||
          User.strict_loading(false).create!(
            email_address: "admin@#{@city.domain}",
            username: "admin_#{@city.slug}",
            password: "password123",
            password_confirmation: "password123",
            city: @city
          )
      end

      Brgen::CityContent.community_slugs_for(@city.country_code).index_with do |slug|
        Community.find_or_create_by!(slug: slug, city: @city) do |community|
          community.name = slug.capitalize
          community.description = "#{@city.name} — #{slug}"
          community.user = admin
        end
      end
    end

    def seed_users
      USERS.each do |_first_name, username|
        @users_by_username[username] = User.strict_loading(false).find_or_create_by!(
          email_address: "#{username}@#{@city.domain}"
        ) do |user|
          user.username = username
          user.password = user.password_confirmation = "password123"
          user.city = @city
          user.latitude = @city.latitude.to_f + rand(-0.04..0.04)
          user.longitude = @city.longitude.to_f + rand(-0.04..0.04)
        end
      end
    end

    def seed_posts(communities)
      POSTS.each do |row|
        next if Post.exists?(city: @city, title: row[:title])

        user = @users_by_username.fetch(row[:user])
        community = communities.fetch(row[:community])

        post = Post.create!(
          user: user,
          city: @city,
          community: community,
          title: row[:title],
          content: row[:content],
          anonymous: row[:anonymous] == true,
          created_at: row[:hours_ago].hours.ago + rand(0..45).minutes
        )
        post.record_activity!("BergenDemoSeed") if post.respond_to?(:record_activity!)

        if @attach_media && row[:image]
          DemoMedia.attach_remote_postpro!(post, :image, seed: row[:image], preset: "landscape")
        end

        seed_comments!(post, row[:comments])

        voters = @users_by_username.values.shuffle
        vote_target = row[:votes].to_i.positive? ? row[:votes].to_i : rand(2..5)
        vote_target.times do |index|
          voter = voters[index % voters.size]
          post.reactions.find_or_create_by!(user: voter, kind: %w[like love].sample)
          post.votes.find_or_create_by!(user: voter) { |vote| vote.value = 1 }
        end
      end
    end

    def seed_listings
      category = Marketplace::Category.first || Marketplace::Category.create!(name: "Diverse", slug: "diverse-bergen")
      base_lat = @city.latitude.to_f
      base_lng = @city.longitude.to_f
      base_lat = 60.3913 if base_lat.zero?
      base_lng = 5.3221 if base_lng.zero?

      LISTINGS.each do |row|
        next if Marketplace::Listing.exists?(title: row[:title])

        user = @users_by_username.fetch(row[:user])
        listing = Marketplace::Listing.create!(
          user: user,
          title: row[:title],
          description: "Hentes i #{@city.name}. PM for detaljer. (Guest kan sende bud uten konto.)",
          price_cents: row[:price_cents],
          category: category,
          location: @city.name,
          latitude: base_lat + rand(-0.03..0.03),
          longitude: base_lng + rand(-0.04..0.04),
          status: "active",
          created_at: rand(2..21).days.ago
        )
        if @attach_media
          DemoMedia.attach_remote_postpro!(listing, :photos, seed: row[:image], preset: "portrait")
        end
      end
    end

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

    def seed_live_posts
      base_lat = @city.latitude.to_f
      base_lng = @city.longitude.to_f
      base_lat = 60.3913 if base_lat.zero?
      base_lng = 5.3221 if base_lng.zero?
      users = @users_by_username.values
      return if users.empty?

      LIVE_NOTES.each_with_index do |row, i|
        # Idempotent: one Live note per body prefix in city
        next if Post.live.where(city: @city).where("content LIKE ?", "#{row[:body][0, 40]}%").exists?

        user = users[i % users.size]
        body = row[:body]
        post = Post.new(
          user: user,
          city: @city,
          content: body,
          title: body.truncate(80),
          created_at: row[:hours_ago].hours.ago + rand(0..20).minutes
        )
        post.stamp_live_location!(
          lat: base_lat + rand(-0.02..0.02),
          lng: base_lng + rand(-0.03..0.03)
        )
        post.save!
        post.record_activity!("BergenLiveSeed") if post.respond_to?(:record_activity!)

        # A few upvotes so Hot tab isn't empty
        users.sample([ 2, users.size ].min).each do |voter|
          post.votes.find_or_create_by!(user: voter) { |vote| vote.value = 1 }
        end
      end
    end

    def seed_playlists
      owner = @users_by_username.fetch("live_bergenlive")
      playlist = Playlist::Playlist.find_or_initialize_by(city: @city, name: RADIO_BERGEN_PLAYLIST, user: owner)
      playlist.assign_attributes(
        description: "AKMD-lokallåter og beat-referanser fra Radio Bergen-manifestet. Nattbuss, tunnel og regnby.",
        public_access: true,
        collaborative: false,
        plays_count: playlist.plays_count.to_i.positive? ? playlist.plays_count : 428
      )
      playlist.save!

      return if playlist.tracks.count >= radio_bergen_manifest_tracks.size

      radio_bergen_manifest_tracks.each do |row|
        track = find_or_create_radio_track!(row, owner: owner)
        playlist.add_track!(track, user: owner)
      end
      playlist.update_column(:tracks_count, playlist.tracks.count) if playlist.tracks_count != playlist.tracks.count
    end

    def seed_dating
      DATING_BIOS.each do |row|
        user = @users_by_username.fetch(row[:user])
        profile = Dating::Profile.strict_loading(false).find_or_initialize_by(user: user)
        profile.assign_attributes(
          bio: row[:bio],
          age: row[:age],
          gender: row[:gender],
          looking_for: row[:looking_for],
          latitude: user.latitude,
          longitude: user.longitude,
          bydel: row[:bydel],
          visible: false
        )
        if @attach_media && !profile.photos.attached?
          DemoMedia.attach_remote_postpro!(profile, :photos, seed: row[:image], preset: "portrait", width: 600, height: 900)
        end
        profile.visible = profile.photos.attached?
        profile.save!
      end
    end

    def seed_comments!(post, bodies)
      rows = Array(bodies).each_with_index.filter_map do |body, index|
        commenter = @users_by_username.values.sample
        created_at = post.created_at + (index + 1).minutes + rand(10..90).seconds
        {
          user_id: commenter.id,
          commentable_type: post.class.name,
          commentable_id: post.id,
          content: body,
          created_at: created_at,
          updated_at: created_at
        }
      end
      Comment.insert_all(rows) if rows.any?
      post.touch
    end

    def seed_dating_likes
      DATING_MUTUAL_PAIRS.each do |a_name, b_name|
        a = @users_by_username.fetch(a_name)
        b = @users_by_username.fetch(b_name)
        Dating::Like.find_or_create_by!(liker: a, likee: b)
        Dating::Like.find_or_create_by!(liker: b, likee: a)
      end

      DATING_ONE_WAY_LIKES.each do |liker_name, likee_name|
        Dating::Like.find_or_create_by!(
          liker: @users_by_username.fetch(liker_name),
          likee: @users_by_username.fetch(likee_name)
        )
      end
    end

    def radio_bergen_manifest_tracks
      @radio_bergen_manifest_tracks ||= begin
        manifest = load_radio_bergen_manifest
        local = Array(manifest["local_mp3"]).map do |row|
          {
            artist: row["artist"],
            title: row["title"],
            source_type: "direct",
            source_url: "#{LOCAL_AUDIO_BASE}#{row['src']}"
          }
        end
        youtube = Array(manifest.dig("external_reference", "youtube")).map do |row|
          {
            artist: row["artist"],
            title: row["title"],
            source_type: "youtube",
            source_url: "https://www.youtube.com/watch?v=#{row['id']}"
          }
        end
        local + youtube
      end
    end

    def load_radio_bergen_manifest
      RadioBergenManifest.load
    end

    def find_or_create_radio_track!(row, owner:)
      Playlist::Track.find_or_create_by!(
        title: row[:title],
        artist: row[:artist],
        source_type: row[:source_type],
        source_url: row[:source_url]
      ) do |track|
        track.user = owner if track.has_attribute?(:user_id)
        track.privacy = "public"
        track.duration_seconds = rand(150..320)
        track.genre = row[:source_type] == "direct" ? "bergen" : "beats"
      end
    end

    def seed_places(neighborhoods)
      return unless defined?(Place) && Place.table_exists?

      PLACES.each do |row|
        next if Place.exists?(city: @city, slug: row[:slug])

        place = Place.create!(
          city: @city,
          neighborhood: neighborhoods[row[:neighborhood]],
          name: row[:name],
          slug: row[:slug],
          kind: row[:kind],
          address: row[:address],
          latitude: row[:latitude],
          longitude: row[:longitude]
        )
        next unless @attach_media && row[:image]

        DemoMedia.attach_remote_postpro!(place, :photo, seed: row[:image], preset: "landscape")
      end
    end

    def seed_takeaway
      RESTAURANTS.each do |row|
        next if Takeaway::Restaurant.exists?(name: row[:name])

        user = @users_by_username.fetch(row[:user])
        restaurant = Takeaway::Restaurant.create!(
          user: user,
          name: row[:name],
          cuisine_type: row[:cuisine_type],
          address: row[:address],
          active: true,
          delivery_fee_cents: row[:delivery_fee_cents],
          min_order_cents: row[:min_order_cents],
          latitude: row[:latitude],
          longitude: row[:longitude],
          rating: row[:rating]
        )
        restaurant.update_column(:city, @city.name) if restaurant.has_attribute?(:city)

        Array(row[:menu]).each do |item_row|
          menu_item = Takeaway::MenuItem.create!(
            restaurant: restaurant,
            name: item_row[:name],
            description: item_row[:description],
            price_cents: item_row[:price_cents],
            available: true
          )
          next unless @attach_media && item_row[:image]

          DemoMedia.attach_remote_postpro!(menu_item, :photo, seed: item_row[:image], preset: "portrait", width: 720, height: 540)
        end
      end
    end

    def seed_tv
      TV_CHANNELS.each do |row|
        user = @users_by_username.fetch(row[:user])
        channel = Tv::Channel.find_or_initialize_by(slug: row[:slug])
        channel.assign_attributes(
          user: user,
          name: row[:name],
          description: row[:description],
          subscribers_count: channel.subscribers_count.to_i.positive? ? channel.subscribers_count : rand(120..2400)
        )
        channel.save!

        if @attach_media
          DemoMedia.attach_remote_postpro!(channel, :avatar, seed: row[:avatar], preset: "portrait", width: 480, height: 480) unless channel.avatar.attached?
          DemoMedia.attach_remote_postpro!(channel, :banner, seed: row[:banner], preset: "landscape", width: 1280, height: 480) unless channel.banner.attached?
        end

        Array(row[:videos]).each do |video_row|
          next if channel.videos.exists?(title: video_row[:title])

          video = Tv::Video.create!(
            user: user,
            channel: channel,
            title: video_row[:title],
            description: "Demo fra #{@city.name}.",
            status: "published",
            duration_seconds: video_row[:duration_seconds],
            views_count: video_row[:views_count],
            published_at: rand(2..45).days.ago
          )
          next unless @attach_media && video_row[:thumbnail]

          DemoMedia.attach_remote_postpro!(video, :thumbnail, seed: video_row[:thumbnail], preset: "landscape", width: 1280, height: 720)
        end
      end
    end
  end
end
