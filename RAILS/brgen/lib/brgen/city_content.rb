# frozen_string_literal: true

require "faker"

module Brgen
  module CityContent
    SUBREDDITS_BY_DOMAIN = {
      "brgen.no" => %w[bergen norge],
      "longyearbyn.no" => %w[longyearbyen norge],
      "oshlo.no" => %w[oslo norge],
      "stvanger.no" => %w[stavanger norge],
      "trmso.no" => %w[tromso norge],
      "trndheim.no" => %w[trondheim norge],
      "reykjavk.is" => %w[reykjavik iceland],
      "kbenhvn.dk" => %w[copenhagen denmark],
      "gtebrg.se" => %w[gothenburg sweden],
      "mlmoe.se" => %w[malmo sweden],
      "stholm.se" => %w[stockholm sweden],
      "hlsinki.fi" => %w[helsinki finland],
      "lndon.uk" => %w[london unitedkingdom],
      "amstrdam.nl" => %w[amsterdam thenetherlands],
      "rottrdam.nl" => %w[rotterdam thenetherlands],
      "lsangeles.com" => %w[LosAngeles california],
      "newyrk.us" => %w[nyc AskNYC],
      "prtland.com" => %w[portland oregon],
      "chcago.us" => %w[chicago illinois],
      "frankfrt.de" => %w[frankfurt germany],
      "mrseille.fr" => %w[marseille france],
      "mlan.it" => %w[milan italy],
      "lisbon.pt" => %w[lisbon portugal]
    }.freeze

    COMMUNITY_SLUGS = {
      "NO" => %w[bergen norge kultur mat musikk],
      "US" => %w[local news food music culture],
      "NL" => %w[amsterdam nederland nieuws eten],
      "GB" => %w[local news food music],
      "DE" => %w[lokal nachrichten essen],
      "FR" => %w[local actualites nourriture],
      "SE" => %w[lokalt nyheter mat],
      "DK" => %w[lokalt nyheder mad],
      "FI" => %w[paikallinen uutiset],
      "IS" => %w[local news],
      "IT" => %w[locale notizie cibo],
      "PT" => %w[local noticias comida],
      "PL" => %w[lokalne wiadomosci],
      "BE" => %w[local actualites],
      "CH" => %w[lokal news],
      "LI" => %w[lokal news]
    }.freeze

    # Faker locale ids, keyed to the same country codes as COMMUNITY_SLUGS, so
    # seeded users get names that actually sound like they're from the city's
    # country instead of generic Faker::Name defaults.
    #
    # These are Faker's own locale ids (the filenames in faker/lib/locales),
    # which are mostly region-tagged: Norwegian data lives in nb-NO.yml, not
    # nb.yml. An earlier version of this table listed bare tags ("nb", "de")
    # to stay inside config.i18n.available_locales, on the theory that a
    # region tag would raise I18n::InvalidLocale. It does raise — but a bare
    # "nb" doesn't fail loudly, it silently resolves to no Norwegian data at
    # all and hands back English: Faker::Config.locale = "nb" then
    # Faker::Name.first_name returned "Jerrell", and Faker::Address.city
    # "Gailborough". So the whole mechanism was a no-op and every city seeded
    # English-sounding people regardless of country.
    #
    # with_faker_locale widens I18n.available_locales for the duration of the
    # block instead, which is what makes the region tags usable. Seeding is
    # also the only caller, so the widening never outlives a seed run.
    LOCALE_BY_COUNTRY = {
      "NO" => "nb-NO",
      "SE" => "sv",
      "DK" => "da-DK",
      "FI" => "fi-FI",
      # Faker ships no Icelandic locale; Norwegian is the nearest Nordic
      # naming stock and reads far less wrong than English for Reykjavík.
      "IS" => "nb-NO",
      "US" => "en-US",
      "GB" => "en-GB",
      "NL" => "nl",
      "DE" => "de",
      "FR" => "fr",
      "BE" => "fr",
      "CH" => "de-CH",
      "LI" => "de-CH",
      "IT" => "it",
      "PT" => "pt",
      "PL" => "pl"
    }.freeze

    # What a city actually sounds like.
    #
    # PerCitySeeder used Faker for every city but Bergen, so oshlo.no and
    # trndheim.no got Norwegian-locale lorem: grammatical, placeless, and in
    # nobody's dialect. A city network whose whole argument is that a visitor on
    # lsangeles.com never sees Bergen cannot seed all four with the same voice.
    #
    # Each bank is written in the city's own dialect, checked against the
    # features the sources actually record rather than an impression of them:
    #
    #   bergensk    `eg`, `ka`, and no feminine gender at all — `boken`,
    #               `jenten`, never `boka`. An e-language: `å hente`, not
    #               `å henta`. Local words: boss (søppel), smau (alley),
    #               kjuagutt (a real Bergenser), hallaien, "den e brun".
    #   trøndersk   `æ`, `itj`, `ka`, `dokker`, `koss`; apokope drops the final
    #               vowel (`å kast`, `mått`); palatalisation writes `mannj`,
    #               `kvellj`; `sjø` closes a sentence for emphasis.
    #   stavangersk `eg` and an a-language — `å kasta`, `ei visa` — with the
    #               plural -ar the city shares with north Rogaland.
    #   oslo        east-Norwegian bokmål with the colloquial feminine kept:
    #               `boka`, `jenta`, `sjæl`. It is the one of the four with no
    #               dialect markers to reach for, and pretending otherwise is
    #               worse than writing it plainly.
    #
    # Places are real and specific. A post about Bybanen or Bakklandet belongs
    # to one city and could not have been generated for another, which is the
    # whole point of the exercise.
    POSTS_BY_DOMAIN = {
      "brgen.no" => [
        [ "Ka gjør dokker når det bøtter ned hele helgen?", "Eg har gitt opp paraplyen. Kjøpte skikkelig regnjakke på Xhibition og nå e det nesten kjekt å gå i sentrum når det står rett ned.",
          [ "Paraply i Bergen e bare noe turistene har. Velkommen etter.", "Regnbukse òg. Da kan du sitte på benken på Torgallmenningen uten å tenke på det." ] ],
        [ "Bosset på Nordnes står igjen fjerde uken", "Nokon som veit ke det går i? Har ringt kommunen to ganger. Bekkalokket i smauet e tett òg.",
          [ "Samme på Møhlenpris. Trur det e noe med ruten.", "Meld det inn på nett, da får du saksnummer. Telefon gir ingenting." ] ],
        [ "Fløyen før klokken sju e en annen by", "Gikk opp i grålysningen i dag. Møtte tre stykker totalt. Byen lå under skodden og bare Ulriken stakk opp.",
          [ "Det e den eneste tiden Fløyen e vår.", "Prøv Stoltzekleiven samme tid. Brutalt, men du har den for deg selv." ] ],
        [ "Beste tebrød i Bergen — eg tar imot forslag", "Har testet meg gjennom sentrum. Fortsatt ikke funnet noe som slår det eg fikk på Møhlenpris i fjor.",
          [ "Baker Brun på Bryggen, men bare før ti.", "Den e brun. Bokstavelig talt." ] ],
        [ "Bybanen til Åsane — trur dokker på 2030?", "Har hørt den datoen så mange ganger nå at eg begynner å lure. Noen som følger med på reguleringen?",
          [ "Eg har hørt den siden eg var student. Nå har eg barn på skolen.", "Følg bystyremøtene, det e der det faktisk avgjøres." ] ],
        [ "Fisketorget lørdag: turist eller bergenser?", "Eg kjøper fortsatt fisken der, men aldri på lørdag. Da e det kø av folk som skal ha reker i beger.",
          [ "Tirsdag morgen. Da e det oss.", "Prøv fiskebutikken i Sandviken i stedet, halve prisen." ] ],
        [ "Kjuagutt søker fotballag i Årstad", "35, treig, men møter opp hver gang. Spilte på Nymark for hundre år siden.",
          [ "Vi trenger folk på torsdager. Send melding.", "Møter opp hver gang e det eneste kravet som betyr noe." ] ],
        [ "Brann på Stadion i regn e den ekte varen", "Bataljonen sto som vanlig. Den e brun, uansett hvordan det gikk.",
          [ "Sto på Store Stå i tre timer. Angrer ingenting.", "Regnet hører til. Sol på Stadion føles feil." ] ]
      ],
      "oshlo.no" => [
        [ "Hvorfor er det alltid kø på Sognsvann når sola kommer?", "Dro dit klokka sju i går for å slippe unna. Klokka ni var det folk overalt. Hele byen har samme idé samtidig.",
          [ "Gå to stopp lenger inn, så har du skogen for deg sjæl.", "Ullevålseter en tirsdag. Da er hytta nesten tom." ] ],
        [ "Grünerløkka er ikke Grünerløkka lenger", "Bodde der fra 2011. Kom tilbake i helga og kjente igjen tre steder. Er det bare meg som syns det gikk fort?",
          [ "Det samme skjedde med Torshov, bare ti år seinere.", "Tøyen holder fortsatt. Foreløpig." ] ],
        [ "Beste kebab øst for Akerselva?", "Har spist meg gjennom Grønland og Tøyen i to år. Kommer stadig tilbake til det samme stedet, men vil gjerne bli overbevist.",
          [ "Si hvilket sted, a. Ellers blir dette bare krangel.", "Alt over Grønland T er turistmat nå. Sola steker og prisen dobles." ] ],
        [ "T-banen til Ekeberg — noen som vet noe?", "Står fast igjen på Jernbanetorget. Tredje gang denne uka. Skjønner ikke hva som skjer med signalanlegget.",
          [ "Fellestunnelen. Det er alltid fellestunnelen.", "Ta 34-bussen når det står. Klokka sju går den fortere enn banen." ] ],
        [ "Nordmarka i september slår Nordmarka i juli", "Ingen mygg, ingen folk, og sopp overalt. Gikk fra Sognsvann til Ullevålseter og møtte fire personer.",
          [ "Og lyset. September-lyset der inne er noe for seg selv.", "Husk hodelykt, det blir mørkt fortere enn du tror." ] ],
        [ "Vippa eller Aker Brygge for folk som besøker?", "Har søskenbarn på besøk fra Bergen og vil ikke ta dem med et sted de kommer til å le av meg for.",
          [ "Vippa. Aker Brygge er for folk som ikke bor her.", "Ta dem til Salt i stedet, så slipper du valget." ] ],
        [ "Bislett om morgenen, hvem løper der?", "Prøver å komme i gang igjen. Er banen åpen for vanlige folk før jobb, eller er det klubbene som har den?",
          [ "Åpen mellom seks og åtte på hverdager. Sjekk skiltet ved inngangen.", "Vi er en gjeng der kvart over seks. Bare møt opp." ] ],
        [ "Operaen-taket er fortsatt gratis og fortsatt best", "Folk glemmer det. Gå opp en tirsdag kveld, ta med kaffe, se utover fjorden. Koster ingenting.",
          [ "Glatt når det regner. Gå med ordentlige sko.", "Best i februar når sola står lavt og det er is på fjorden." ] ]
      ],
      "stvanger.no" => [
        [ "Kor mange turistar tåler Preikestolen?", "Var der i går og det stod folk i kø på sjølve platået. Eg er glad folk kjem, men det byrjar å bli mykje.",
          [ "Gå opp klokka fem. Då har du han åleine i ein time.", "Kjerag er like fint og halvparten så fullt." ] ],
        [ "Fargegaten i regn er faktisk finare", "Alle tar bilete når sola skin, men Øvre Holmegate i regnvêr er noko for seg sjølv. Fargane blir mettare.",
          [ "Sant. Og då er det ingen som står i vegen for biletet.", "Same med Gamle Stavanger. Regn kler kvitmåling." ] ],
        [ "Nokon som handlar fisk i Vågen framleis?", "Eg gjer det kvar fredag. Byrjar å bli få av oss, verkar det som.",
          [ "Eg gjer det, men tidleg. Etter elleve er det berre turistar.", "Fiskebutikken på Storhaug er betre og billegare." ] ],
        [ "Oljemuseet med ungar — verdt det?", "Har to på seks og ni. Er det noko å sjå på for dei, eller blir det for mykje tekst på veggane?",
          [ "Ungane mine brukte to timar i klatreriggen ute. Museet såg dei knapt.", "Ta med niåringen, seksåringen blir lei." ] ],
        [ "Tou Scene har blitt bra igjen", "Var der på konsert i helga. Lokalet fungerer betre no enn for fem år sidan.",
          [ "Lyden er endeleg fiksa. Det var problemet heile tida.", "Bryggeriet ved sida av er verdt turen åleine." ] ],
        [ "Sykla til Sola mot vinden i dag", "Tjue minutt ut, ti minutt heim. Slik er det å bu her.",
          [ "Det er alltid motvind begge vegar. Det er fysikken i Rogaland.", "Ta Hafrsfjord-ruta, du ligg meir i le." ] ],
        [ "Gamle Stavanger er tomt om vinteren", "Gjekk gjennom kvitbyen i går kveld og møtte ingen. Litt trist, litt fint.",
          [ "Det er då han er finast. Om sommaren kjem du deg ikkje fram.", "Folk bur der framleis, dei held seg berre inne." ] ],
        [ "Breiavatnet-svanene har fått ungar igjen", "Sju stykk. Stod og såg på dei i tjue minutt før eg gjekk på jobb.",
          [ "Sju er mange. I fjor var det fire.", "Ikkje mat dei med brød. Det er ikkje bra for dei." ] ]
      ],
      "trndheim.no" => [
        [ "Ka gjør dokker på Solsiden når det regn?", "Æ har prøvd alt. Til slutt blir det bare å sett sæ inne og vent, sjø.",
          [ "Æ går te Bakklandet i stedet. Smalere gater, mindre vind.", "Regnet kommer sidelengs der ute. Det e ingen vits." ] ],
        [ "Bakklandet e fullt av folk som itj bor her", "Skjønne det godt, det e jo fint. Men det e blitt vanskelig å få bord nå.",
          [ "Prøv en onsdag. Da e det oss som bor her.", "Møllenberg e det Bakklandet var for ti år sia." ] ],
        [ "Koss kjem æ mæ opp Trampen uten å se dum ut?", "Har bodd her i tre år og itj klart det enda. Noen som har en teknikk?",
          [ "Høyre fot på plata, strak arm, len dæ bakover. Itj se ned.", "Alle ser dumme ut første gangen. Det e en del av det." ] ],
        [ "Nidelva om morran e det beste med byen", "Går langs elva til jobb hver dag. Tar ti minutt lenger, verdt det hver gang.",
          [ "Fra Gamle Bybro og nedover e det finest.", "Om vinteren når det ryk av elva. Da e det noe helt anna." ] ],
        [ "Gløshaugen-kantina — kor et dokker egentlig?", "Æ e lei av det samme. Noen som har funnet noe bedre i gåavstand?",
          [ "Realfagbygget har bedre utvalg enn hovedbygget.", "Ta med matpakke og sett dæ i parken. Billigere og bedre." ] ],
        [ "Munkholmen siste båt i september", "Rakk den så vidt i fjor. Noen som vet om de kjører ut oktober i år?",
          [ "De pleie å stopp rundt månedsskiftet. Sjekk rutetabellen.", "Siste turen e den beste. Ingen folk, og lyset e lavt." ] ],
        [ "Samfundet på en tirsdag e undervurdert", "Ingen kø, folk prater faktisk sammen. Helgene e itj det samme.",
          [ "Klubben på tirsdag e den ekte varen.", "Enig. Æ slutta å gå i helgene for to år sia." ] ],
        [ "Tyholttårnet snurre fortsatt, eller?", "Sto og så på det i går og klarte itj å avgjøre om det gikk rundt.",
          [ "Restauranten snurre, tårnet står stille. Det e derfor du itj ser det.", "En runde tar en time. Du må stå der lenge for å merke det." ] ]
      ]
    }.freeze

    module_function

    # Nil when the city has no bank, so the caller keeps its Faker path rather
    # than seeding a Bergen post under a Trondheim domain.
    def posts_for(domain)
      POSTS_BY_DOMAIN[domain.to_s]
    end

    def subreddits_for(domain)
      SUBREDDITS_BY_DOMAIN.fetch(domain) { [ domain.to_s.split(".").first ] }
    end

    def community_slugs_for(country_code)
      COMMUNITY_SLUGS.fetch(country_code.to_s.upcase, COMMUNITY_SLUGS["US"])
    end

    def locale_for(country_code)
      LOCALE_BY_COUNTRY.fetch(country_code.to_s.upcase, LOCALE_BY_COUNTRY["US"])
    end

    # Run a block with Faker speaking the city's language.
    #
    # Faker resolves its data through the host app's I18n backend, so a locale
    # the app doesn't declare raises I18n::InvalidLocale — and the app only
    # declares the five it ships UI copy for. Both the allowlist and
    # Faker::Config.locale are process-global, so both are restored on the way
    # out; a seed_all! run over many cities would otherwise leak the last
    # city's locale into everything after it.
    def with_faker_locale(country_code)
      locale = locale_for(country_code)
      previous_available = I18n.available_locales
      previous_locale = Faker::Config.locale

      I18n.available_locales = (previous_available + [ locale.to_sym ]).uniq
      Faker::Config.locale = locale
      yield
    ensure
      Faker::Config.locale = previous_locale
      I18n.available_locales = previous_available
    end
  end
end
