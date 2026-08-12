# frozen_string_literal: true

module Brgen
  module PlausibleContent
    # Post titles, openers and closers.
    #
    # Split out of plausible_content.rb, which stood at 512 code lines against a
    # 344 ceiling. These pools are the bulk of it and only post_title/post_body
    # read them, so they move as a unit.
    module Prose
      # --- Posts -------------------------------------------------------------

      # Interpolate %{city} so these work for any Norwegian city domain.
      #
      # 39 of these produced 1447 posts on brgen.no, so the top title appeared 42
      # times and the feed read as generated even after the Latin was gone. The
      # repetition was the giveaway, not the language. Widened to a bit over a
      # hundred here, and the bodies below are now composed from two pools rather
      # than picked whole, which is where the real multiplier is.
      #
      # Deliberately generic within Norwegian city life. "Bybanen" was in this list
      # and is Bergen's light rail — the header above says no Bergen-only
      # landmarks, and it read as nonsense on oshlo.no. Same for the old title
      # asking whether to take the train to Oslo, on a site whose city is Oslo.
      NORWEGIAN_POST_TITLES = [
      # transport and getting about
      "Noen som vet når kollektivtrafikken går som normalt igjen?",
      "Parkering i sentrum — hva gjør folk egentlig?",
      "Hva er egentlig greia med parkeringsappene?",
      "Hvordan kommer man seg til flyplassen tidlig morgen?",
      "Er det noen som kjører samme vei og vil dele bil?",
      "Hvor lang tid bruker dere egentlig til jobb?",
      "Nattbussen — går den fortsatt i helgene?",
      "Sykkelvei eller hovedvei, hva velger dere?",
      "Noen som vet hvorfor bussen aldri kommer i rushen?",
      "Er månedskort verdt det når man jobber hjemmefra halve uka?",
      "Hvem har best pris på dekkskifte?",
      "Anbefalinger til bilverksted?",
      "Hvem fikser sykkel raskt og billig?",
      "Leier noen ut garasjeplass i nærheten av sentrum?",

      # mat og drikke
      "Beste kaffe i %{city} akkurat nå?",
      "Hvor spiser man best fiskesuppe?",
      "Hvor får man tak i skikkelig godt brød?",
      "Noen som har prøvd den nye kaffebaren?",
      "Beste pizza i byen — og nei, ikke kjedene",
      "Hvor kjøper dere fisk som ikke er frossen?",
      "Finnes det et sted som lager ordentlig suppe til lunsj?",
      "Anbefal en restaurant for en litt spesiell anledning",
      "Hvor kan man sitte ute og spise når været først er bra?",
      "Noen som vet om et bakeri som har åpent tidlig?",
      "Er det noen gode matbutikker utenom de vanlige?",
      "Hvor finner man grønnsaker som ikke er pakket i plast?",

      # bolig og hjem
      "Ledig plass i kollektiv fra 1. neste måned",
      "Hva er normalt å betale i depositum nå?",
      "Noen som har leid ut gjennom de nye plattformene?",
      "Hvor mye betaler folk i strøm nå?",
      "Anbefalinger til rørlegger i %{city}?",
      "Elektriker som svarer på telefonen — finnes det?",
      "Hvem har malt leiligheten selv og angret?",
      "Er det verdt å bytte til varmepumpe i en gammel leilighet?",
      "Noen som vet om ledig kontorplass?",
      "Hvordan finner man en snekker som har tid før jul?",
      "Fukt i kjelleren — hvem ringer man først?",

      # barn og familie
      "Regnet igjen — tips til innendørs aktiviteter med barn?",
      "Noen erfaring med barnehagene i %{city}?",
      "Tips til bursdagsfeiring for femåring",
      "Hvilke aktiviteter finnes for barn på vinteren?",
      "Er det noen barselgrupper som fortsatt møtes?",
      "Hvor går man med barn en regnfull lørdag?",
      "Noen som vet om gode fritidsaktiviteter for tenåringer?",
      "Sitter dere også fast i leksene på femte trinn?",

      # ute og vær
      "Noen som vil bli med på tur på søndag?",
      "Tips til turer når det blåser for mye på fjellet",
      "Turgruppe for nybegynnere?",
      "Beste badeplass når det først er varmt",
      "Hvor går man tur når det er glatt overalt?",
      "Er det noen som løper fast om morgenen?",
      "Hvilken tur tar dere med besøk som ikke er i form?",
      "Noen som vet om hyttene er åpne nå?",
      "Hva pakker dere egentlig med på dagstur?",

      # kjøp og salg
      "Selger sykkel, hvor er det lurt å legge ut?",
      "Loppemarked til helgen",
      "Gode brukthandler i %{city}?",
      "Bytter bort to konsertbilletter",
      "Noen som vet hvor man selger møbler raskt?",
      "Kjøpte brukt og angrer — hva er reglene egentlig?",
      "Hvor får man tak i brukt sportsutstyr til barn?",
      "Er det noen bytteringer for klær her?",
      "Hva er en fornuftig pris for en ti år gammel bil?",

      # kultur og det som skjer
      "Konsertanbefalinger denne måneden",
      "Åpner det noe nytt i sentrum til høsten?",
      "Nye åpningstider på biblioteket",
      "Hva gjør man en søndag når alt er stengt?",
      "Er det noe som skjer på tirsdager i det hele tatt?",
      "Noen som har vært på den nye utstillingen?",
      "Hvor finner man konserter som ikke koster en formue?",
      "Er kinoen fortsatt like dyr som jeg husker?",
      "Noen som vil starte en lesesirkel?",

      # tjenester og helse
      "Anbefal en tannlege som tar nye pasienter",
      "Hvor finner jeg en god frisør?",
      "Fastlege som tar nye pasienter — noen tips?",
      "Er det verdt å bli medlem på treningssenteret?",
      "Noen som har god erfaring med fysioterapeut her?",
      "Hvor lang er ventetiden hos optiker for tiden?",
      "Hvem vasker vinduer til en fornuftig pris?",

      # jobb og studier
      "Beste stedet å jobbe med laptop i %{city}?",
      "Noen som har byttet bransje etter fylte førti?",
      "Er det noen som jobber turnus og vil bytte vakter?",
      "Hvor finner studenter jobb ved siden av studiene?",
      "Er det noen kontorfellesskap som ikke koster skjorta?",

      # dyr
      "Fant en katt i går — noen som savner den?",
      "Hundeluftere i nærheten — hvor går dere?",
      "Noen som kan anbefale en veterinær?",
      "Er det lov å ha hund med på bussen?",

      # praktisk og kommunalt
      "Hvor kaster man elektronisk avfall?",
      "Noen som skjønner seg på søppelsorteringen her?",
      "Hvem kontakter man om en gatelykt som ikke virker?",
      "Er det noen som har fått svar fra kommunen på noe som helst?",
      "Hvor melder man fra om hull i veien?",
      "Snømåking — hvem har egentlig ansvaret utenfor huset?",

      # nabolag og løst og fast
      "Savner noen en blå sekk fra bussen?",
      "Er det noen som spiller fotball på tirsdager?",
      "Noen som vil være med å starte en dugnad i gata?",
      "Nabolaget har blitt stille — hvor er alle?",
      "Hvem andre her har bodd i samme leilighet i over ti år?",
      "Er det noen som fortsatt bruker torget?",
      "Hva savner dere mest i denne bydelen?",
      "Noen som husker hva som lå der før?"
      ].freeze

      # Bodies are composed, not picked whole: one opening sentence and one closing
      # sentence, drawn separately. Ten whole bodies across 1447 posts meant each
      # one appeared about 145 times; 30 openings against 24 closings is 720
      # combinations from 54 sentences, and every pairing still reads as something
      # a person would write because each half stands alone.
      #
      # Kept as two flat pools rather than a template with slots. A slot grammar
      # produces sentences no one wrote and it shows — the point of this file is
      # that the seed data does not announce itself.
      NORWEGIAN_POST_OPENERS = [
      "Har prøvd et par steder, men vil gjerne høre hva folk her mener.",
      "Sto en halvtime i går og lurer på om det bare var meg.",
      "Ny i byen og prøver å finne ut hvordan ting fungerer her.",
      "Har lest litt rundt, men finner ikke noe oppdatert.",
      "Vi er to stykker som planlegger dette.",
      "Ikke noe hastverk, men greit å ha på plass før høsten.",
      "Prisene varierer veldig, så jeg prøver å få en peiling først.",
      "Takk til alle som svarte forrige gang — det hjalp faktisk.",
      "Litt usikker på om dette er rett sted å spørre.",
      "Har bodd her i noen år nå og oppdager stadig nye steder.",
      "Dette har jeg lurt på lenge uten å komme noen vei.",
      "Spurte om det samme i fjor, men da var svarene sprikende.",
      "Flyttet hit i vinter og kjenner fortsatt ikke byen så godt.",
      "Har googlet meg i hjel og blir bare mer forvirret.",
      "Kanskje et dumt spørsmål, men jeg tar sjansen.",
      "Noen på jobb nevnte det, og nå går jeg og tenker på det.",
      "Har fått tre helt forskjellige svar fra tre forskjellige folk.",
      "Prøvde det som ble anbefalt her sist, og det funket ikke helt.",
      "Sitter og planlegger neste måned og har gått i stå.",
      "Var innom i går, men det var stengt uten forklaring.",
      "Har utsatt dette altfor lenge og bør bare få det gjort.",
      "Var sikker på at jeg visste svaret, helt til jeg skulle bruke det.",
      "Snakket med naboen om dette, og hun lurte på det samme.",
      "Har spart til dette en stund og vil ikke bomme.",
      "Fant en gammel tråd om det samme, men den er fra 2019.",
      "Skal ha besøk til helgen og vil gjerne ha noe på plass.",
      "Har prøvd å ringe, men kommer aldri gjennom.",
      "Dette burde vært lett å finne ut av, og likevel.",
      "Jobber litt rart for tiden og må planlegge deretter.",
      "Har hørt begge deler, og nå vet jeg ærlig talt ikke."
      ].freeze

      NORWEGIAN_POST_CLOSERS = [
      "Alle tips mottas med takk.",
      "Trenger ikke være dyrt, bare bra.",
      "Noen andre som har opplevd det samme?",
      "Håper noen her vet mer.",
      "Det er plass til noen flere hvis noen vil henge på.",
      "Sender gjerne detaljer på DM.",
      "Del gjerne deres favoritter.",
      "Setter stor pris på konkrete forslag.",
      "Skriv gjerne selv om du bare har en halv anelse.",
      "Er det noen som har gjort dette nylig?",
      "Fint om noen kan bekrefte før jeg bestemmer meg.",
      "Tar imot både gode og dårlige erfaringer.",
      "Helst noe i nærheten, men jeg kan reise litt.",
      "Svar gjerne her, så slipper andre å spørre om det samme.",
      "Har dere en favoritt dere holder hemmelig?",
      "Er det verdt bryet, eller skal jeg bare la det ligge?",
      "Gi lyd hvis du vet om noe.",
      "Hva ville dere gjort?",
      "Sier fra hvis jeg finner ut av det selv.",
      "Takk på forhånd til den som gidder å svare.",
      "Er det noe jeg har oversett her?",
      "Kan godt legge ut hva jeg lander på etterpå.",
      "Trenger ikke noe fancy, bare noe som fungerer.",
      "Håper det er greit å spørre om sånt her."
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
      "Flea market this weekend",
      "How long does everyone's commute actually take?",
      "Is the monthly travel pass worth it these days?",
      "Where do you buy bread that's worth the money?",
      "Anyone tried the new place on the corner?",
      "Recommendations for somewhere to eat for an occasion?",
      "What's a normal deposit to pay around here now?",
      "Electrician who answers the phone — do they exist?",
      "What are people paying for electricity at the moment?",
      "Where do you take kids on a wet Saturday?",
      "Any beginner-friendly walking groups?",
      "Best swimming spot once it's actually warm",
      "Where's the fastest place to sell furniture?",
      "Where do you find secondhand kit for kids?",
      "Concert recommendations this month?",
      "Anything new opening in the centre this autumn?",
      "Dentist taking new patients — any suggestions?",
      "Is the gym membership worth it?",
      "Best place to work on a laptop in %{city}?",
      "Found a cat yesterday — is anyone missing one?",
      "Where does electronic waste go?",
      "Who do you call about a streetlight that's out?",
      "Does anyone still use the square?",
      "What do you miss most in this part of town?",
      "Anyone remember what used to be there?"
      ].freeze

      ENGLISH_POST_OPENERS = [
      "I've tried a couple of places but would rather hear what people here think.",
      "Waited half an hour yesterday and wondered whether it was just me.",
      "New in town and still working out how things run here.",
      "I've read around a bit but can't find anything current.",
      "There are two of us planning it.",
      "No rush, but good to have sorted before autumn.",
      "Prices seem to vary wildly, so I'm trying to get a sense of it first.",
      "Thanks to everyone who answered last time — it genuinely helped.",
      "Not sure this is the right place to ask, but here goes.",
      "I've lived here a few years and still keep finding new places.",
      "This has been bugging me for ages and I've got nowhere with it.",
      "Someone at work mentioned it and now I can't stop thinking about it.",
      "I've had three different answers from three different people.",
      "Tried what was suggested here last time and it didn't quite work.",
      "Been putting this off far too long and should just get on with it.",
      "Found an old thread about the same thing, but it's from 2019.",
      "Got people visiting at the weekend and would like it sorted.",
      "I've tried ringing but can never get through.",
      "Thought I knew the answer until I actually needed it."
      ].freeze

      ENGLISH_POST_CLOSERS = [
      "Any tips appreciated.",
      "Doesn't need to be fancy, just good.",
      "Anyone else run into this?",
      "Hoping someone here knows more.",
      "There's room for a few more if anyone wants to come along.",
      "Happy to send details by DM.",
      "Do share your favourites.",
      "Specific suggestions very welcome.",
      "Chime in even if you've only half an idea.",
      "Has anyone done this recently?",
      "Would be good to have it confirmed before I commit.",
      "Good and bad experiences both welcome.",
      "Ideally nearby, but I can travel a bit.",
      "Answer here and save the next person asking.",
      "Is it worth the bother, or should I let it go?",
      "What would you do?",
      "I'll report back if I work it out myself.",
      "Thanks in advance to anyone who bothers."
      ].freeze
    end
  end
end
