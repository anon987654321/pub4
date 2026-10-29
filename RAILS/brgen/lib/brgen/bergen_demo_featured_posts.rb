# frozen_string_literal: true

module Brgen
  # The featured Bergen demo posts; BergenDemoData re-exports them as FEATURED_POSTS.
  module BergenDemoFeaturedPosts
    FEATURED_POSTS = [
      {
        user: "live_bergenlive", community: "bergen", hours_ago: 1, votes: 9,
        title: "Jeg fant en helt absurd sofa på markedsplassen",
        content: "Åpnet markedsplassen for å se etter en lampe. To minutter senere satt jeg og vurderte en limegrønn 70-tallssofa fra Laksevåg som heter 'Kometen'. Jeg trenger den ikke. Jeg trenger Kometen.",
        comments: [
          "Du trenger Kometen. Dette er åpenbart.",
          "Legg ut link før noen andre tar den.",
        ]
      },
      {
        user: "marte_kode24", community: "bergen", hours_ago: 2, votes: 8,
        title: "Hvorfor oppdager jeg nye smau hver gang jeg bruker Maps?",
        content: "Har brukt maps.brgen.no mest som kart til nå, men zoomet inn i går kveld og fant en liten passasje jeg aldri har lagt merke til. Nå har jeg lyst til å gå byen på kryss og tvers bare for å finne flere.",
        comments: [
          "Samme. Kart er blitt en egen hobby.",
          "Lag en tråd med de beste funnene.",
        ]
      },
      {
        user: "live_bergenlive", community: "musikk", hours_ago: 3, votes: 10,
        title: "Radio Bergen trenger én låt du alltid setter på etter midnatt",
        content: "Ikke gi meg 'den beste låten'. Gi meg den låten som får nattbussen til å føles som en filmscene. Radio Bergen-listen trenger flere sånne.",
        comments: [
          "J Dilla når regnet treffer bussruta.",
          "Noe fra Röyksopp klokka 01:17. Hver gang.",
        ]
      },
      {
        user: "ola_nordnes", community: "mat", hours_ago: 4, votes: 9,
        title: "Takeaway-spørsmålet som splitter kollektivet vårt",
        content: "Vi er fire voksne mennesker og har brukt 47 minutter på å diskutere om vi skal bestille pizza, ramen eller bare spise knekkebrød hjemme. Er det bedre å velge først og angre, eller fortsette møtet?",
        comments: [
          "Ramen. Møtet er over.",
          "takeaway.brgen.no er farlig etter lønningsdag.",
        ]
      },
      {
        user: "sofie_regnby", community: "kultur", hours_ago: 5, votes: 7,
        title: "TV på nett, men faktisk fra Bergen",
        content: "Har sett gjennom Bergen Live på tv.brgen.no og liker at det ikke føles som enda en kanal som prøver å være Netflix. Små konserter, lokale folk, rare innslag. Mer av dette.",
        comments: [
          "Open mic-videoen var overraskende gøy.",
          "Håper noen begynner å filme klubbscenen også.",
        ]
      },
      {
        user: "henrik_vestland", community: "bergen", hours_ago: 6, votes: 8,
        title: "Første date: kaffe, fjell eller bare gå?",
        content: "Noen kompiser mener dating i Bergen begynner med kaffe. Jeg mener det begynner med 'har du regnjakke?'. Hva fungerer faktisk når man skal møte noen for første gang?",
        comments: [
          "Gå. Da kan dere avslutte uten den klassiske kaffe-avslutningen.",
          "dating.brgen.no burde ha en egen 'regn og dårlig plan'-filter.",
        ]
      },
      {
        user: "kari_bybanen", community: "bergen", hours_ago: 7, votes: 6,
        title: "Messenger eller 'send meg på Messenger' og så blir det borte?",
        content: "Har begynt å bruke messenger.brgen.no til lokale ting fordi jeg faktisk finner igjen samtalene. Nå irriterer jeg meg over hvor mange grupper jeg har på andre steder som heter 'Ny gruppe 4'.",
        comments: [
          "Det er navnet 'Ny gruppe 4' som holder samfunnet sammen.",
          "Enig. Pinned samtaler alene er verdt byttet.",
        ]
      },
      {
        user: "ingrid_ulriken", community: "bergen", hours_ago: 9, votes: 7,
        title: "Gratis helgeplan: velg et fjell og en helt tilfeldig kafé",
        content: "Prøver noe nytt på søndag: gå opp et sted jeg ikke pleier å gå, og velge kafé etter hvor våt jeg er når jeg kommer ned. Ingen anmeldelser. Ingen optimalisering.",
        comments: [
          "Det der er kanskje den mest bergenske planen jeg har hørt.",
          "Regelen bør være maks fem minutter kø.",
        ]
      },
      {
        user: "anders_fisketorget", community: "mat", hours_ago: 11, votes: 6,
        title: "Hvorfor er den beste middagen ofte den som ikke var planlagt?",
        content: "Skulle egentlig lage pasta. Endte med å kjøpe fisk, sitte ved Vågen og spise altfor sent. Byen bestemte middagen for meg. Har dere en 'det bare skjedde'-middag dere fortsatt snakker om?",
        comments: [
          "Kom hjem med blåskjell og naboens barn på slep. Ti av ti kveld.",
          "Bergen er best når ingen har laget et regneark.",
        ]
      },
      {
        user: "jonas_7fjell", community: "bergen", hours_ago: 13, votes: 7,
        title: "Kan vi slutte å late som vi går fort i oppoverbakke?",
        content: "Møtte en fyr på Fløyen som gikk så fort at jeg begynte å løpe for å ikke se dum ut. Fem minutter senere var han borte og jeg måtte late som jeg bare 'testet puls'.",
        comments: [
          "Han bor sannsynligvis på Fløyen.",
          "Alle møter sin egen grense på Stoltzen.",
        ]
      },
      {
        user: "hanne_sandviken", community: "bergen", hours_ago: 15, votes: 5,
        title: "Hvem bestemte at alle flytteesker skulle bli permanent interiør?",
        content: "Flyttet for åtte måneder siden. Har fortsatt én stol, tre esker og en lampe som står på gulvet. På et tidspunkt blir dette minimalistisk, ikke sant?",
        comments: [
          "Det er ikke rot før du inviterer folk hjem.",
          "Bruk markedsplassen. Noen trenger akkurat den lampen.",
        ]
      },
      {
        user: "per_laksevag", community: "musikk", hours_ago: 17, votes: 8,
        title: "Den mest Bergen-aktige lyden jeg vet om",
        content: "Ikke måker. Ikke regn. Bybanen som bremser ved stoppet mens noen løper de siste tre meterne. Det er byens trommemaskin.",
        comments: [
          "Regn mot markise på en kafé er nummer to.",
          "Lydopptak når?",
        ]
      },
      {
        user: "silje_korall", community: "kultur", hours_ago: 19, votes: 6,
        title: "Hva burde vært en egen kanal på Brgen?",
        content: "Vi har musikk, kultur, mat, steder og alt mulig annet, men hva savner dere? Jeg vil ha en helt useriøs 'ting som bare skjer i Bergen'-kanal.",
        comments: [
          "Ja. Gjerne med bilder som ser ut som de ikke var planlagt.",
          "Og egne tråder for rare lyder fra naboens leilighet.",
        ]
      },
      {
        user: "magnus_student", community: "bergen", hours_ago: 21, votes: 6,
        title: "Jeg prøvde å bruke Brgen uten å kjenne en eneste funksjon",
        content: "Klikket rundt som en ny bruker og endte på markedsplassen, kartet og radioen før jeg fant tilbake til feeden. Det er egentlig et godt tegn. Det er mye mer by enn meny.",
        comments: [
          "Samme her. Første gang skjønte jeg ikke hvor mye som lå under samme innlogging.",
          "Det er nettopp derfor vertikalene bør føles som steder, ikke knapper.",
        ]
      },
      {
        user: "live_bergenlive", community: "musikk", hours_ago: 23, votes: 7,
        title: "Send meg den rareste konserten du har vært på",
        content: "Min er fortsatt et band i et rom så lite at trommeslageren måtte spille med albuen for å få plass. Publikum var 17 mennesker. Alle trodde de var venner.",
        comments: [
          "Spilte bass i en kjeller med tre takhøyder. Ingen kunne stå helt oppreist.",
          "Dette er jo akkurat hvorfor lokale konserter er morsomme.",
        ]
      },
      {
        user: "emilie_floyen", community: "bergen", hours_ago: 25, votes: 5,
        title: "Brukte kartet til å planlegge en helt meningsløs tur",
        content: "Valgte tre steder på maps.brgen.no jeg aldri hadde besøkt og gikk mellom dem uten en annen plan. Endte på en benk med utsikt over byen og brukte resten av kvelden der. 0 prosent effektivitet.",
        comments: [
          "Perfekt bruk av internett.",
          "Det er en bedre søndag enn en 'optimal' søndag.",
        ]
      },
      {
        user: "ola_nordnes", community: "mat", hours_ago: 27, votes: 6,
        title: "Hva er retten du bestiller når hjernen har logget av?",
        content: "Min er noe sterkt, varmt og mulig å spise foran TV-en. Null beslutninger. Null oppvask. Bare seier.",
        comments: [
          "Døner. Ingen diskusjon.",
          "Ramen når jeg later som jeg er et menneske med kontroll.",
        ]
      },
      {
        user: "marte_kode24", community: "bergen", hours_ago: 30, votes: 7,
        title: "Bergen trenger en byttehandel for folk som har for mye ting",
        content: "Jeg har tre ladere jeg ikke vet hva de passer til, en lampe jeg aldri liker og et kjøkkenapparat jeg brukte én gang. Vi burde bare bytte ting direkte med hverandre.",
        comments: [
          "Dette burde egentlig bo på markedsplassen.",
          "Ja, en 'gratis/bytte'-seksjon hadde fått fart på mye.",
        ]
      },
      {
        user: "sofie_regnby", community: "kultur", hours_ago: 33, votes: 5,
        title: "Har TV en plass for små historier, ikke bare store saker?",
        content: "Jeg vil heller se fem minutter om en person som samler på gamle skilt enn tjue minutter om enda en paneldebatt. Små lokale historier er ofte mye mer interessante.",
        comments: [
          "Ja. Nabohistorier, rare jobber, gamle butikker, alt.",
          "Bergen Live kunne gjort en hel serie av det.",
        ]
      },
      {
        user: "kari_bybanen", community: "bergen", hours_ago: 36, votes: 5,
        title: "Hva burde Brgen klare å få meg til å gjøre i virkeligheten?",
        content: "Dette er testen for meg: ikke hvor mange sider vi har, men om jeg ender opp med å kjøpe noe brukt, møte noen, dra på konsert, finne en tur eller spise et nytt sted fordi jeg var innom.",
        comments: [
          "Eller bare møte naboen du har bodd ved siden av i tre år.",
          "Akkurat. Nettet er mest interessant når det sender deg ut døra.",
        ]
      },
    ].freeze
  end
end
