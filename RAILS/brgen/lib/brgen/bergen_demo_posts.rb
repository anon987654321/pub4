# frozen_string_literal: true

module Brgen
  # The curated Bergen demo posts; BergenDemoData re-exports them as POSTS.
  module BergenDemoPosts
    POSTS = [  # Curated fictional conversation starters for disclosed demos.
      {
        user: "emilie_floyen", community: "bergen", hours_ago: 1, votes: 14,
        title: "Hva skjer i Bergen i helgen?",
        content: "Fredag: standup på Logen, lørdag Pepperkakebyen med nevøen, søndag kanskje tur på Damsgårdsfjellet. Hva er deres planer — og er det noe jeg bommer på?",
        comments: [
          "VilVite har familiedag lørdag, verdt en tur.",
          "Kolonialen brunch søndag hvis dere vil ha rolig start.",
        ]
      },
      {
        user: "live_bergenlive", community: "musikk", hours_ago: 2, votes: 12,
        title: "Radio Bergen-playlisten er oppe — hvem lager neste?",
        content: "Har lagt inn AKMD-lokallåter og beat-referanser fra manifestet vårt. Perfekt til nattbuss hjem fra sentrum. Legg gjerne inn egne funn i kommentarene.",
        image: "bergen-radio-night", comments: [
          "Elsker Sandviken Hotell B — instant nostalgi.",
          "Kan noen lage en ren AKMD-only variant?",
        ]
      },
      {
        user: "emilie_floyen", community: "bergen", hours_ago: 3, votes: 11,
        title: "Sol på Fløyen — verdt hele turen",
        content: "Tok Fløibanen opp før jobb. Utsikten over Vågen var helt vill i morgensola. Anbefaler å komme før kl 09 hvis dere vil unngå kø.",
        image: "bergen-floyen-morning", comments: [
          "Var der i går! Magisk.",
          "Husk varm jakke på toppen, blåser alltid.",
        ]
      },
      {
        user: "henrik_vestland", community: "bergen", hours_ago: 5, votes: 9,
        title: "Regnværsdag på Bryggen",
        content: "Sitter på Kaffebrenneriet og hører regnet mot taket. Hvor er favorittstedet deres når det øser ned?",
        image: "bergen-bryggen-rain", comments: [
          "Dampen på Torget, alltid.",
          "Biblioteket + kaffe fra Godt Brød.",
        ]
      },
      {
        user: "kari_bybanen", community: "norge", hours_ago: 6, votes: 10,
        title: "Bybanen forsinket igjen?",
        content: "Står på Florida og det kommer ingen avgang mot sentrum. Noen som vet om det er signalfeil?",
        comments: [
          "Ja, meldt på Skyss-appen nå.",
          "Ta buss 12 som backup hvis du har det travelt.",
        ]
      },
      {
        user: "marte_kode24", community: "bergen", hours_ago: 7, votes: 8,
        title: "Dating i Bergen — ghosting eller bare regn?",
        content: "Tredje match denne uka som foreslår kaffe på Møhlenpris og så forsvinner. Er dette en bygreie, eller bare meg?",
        comments: [
          "Regn + travel hverdag, folk prioriterer om.",
          "Prøv aktiv date — Fløyen eller VilVite, mindre press.",
        ]
      },
      {
        user: "ola_nordnes", community: "mat", hours_ago: 9, votes: 7,
        title: "Beste kanelbolle i sentrum?",
        content: "Jeg sverger til Baker Hansen, men kollegaen mener Godt Brød er bedre. Hva stemmer folket for?",
        image: "bergen-bakery", comments: [
          "Baker Hansen når de er ferske.",
          "Colonialen på Nordnes er undervurdert.",
        ]
      },
      {
        user: "ingrid_ulriken", community: "bergen", hours_ago: 10, votes: 8,
        title: "Pepperkakebyen — tips før første gang?",
        content: "Skal dit med søster og to barn (6 og 9). Hva bør vi forhåndsbooke, og når er det minst kø?",
        image: "bergen-pepperkakebyen", comments: [
          "Tidlig ettermiddag på hverdag er best.",
          "Ta med termos, køen ved karrusellen kan bli lang.",
        ]
      },
      {
        user: "ingrid_ulriken", community: "bergen", hours_ago: 14, votes: 6,
        title: "Ulriken i kveld — hvem blir med?",
        content: "Planlegger tur opp Ulriken rundt 18. Rolig tempo, kanskje mat på toppen. DM om du vil henge.",
        image: "bergen-ulriken-trail", comments: [
          "Er med! Har ekstra hodelykt.",
          "Sjekk værmeldingen først, skyer ruller inn fort.",
        ]
      },
      {
        user: "magnus_student", community: "bergen", hours_ago: 16, votes: 7,
        title: "UiB-eksamen og ingen plass på biblioteket",
        content: "Alle plassene på HF-bib er borte. Tips til stille leseplasser i sentrum etter kl 16?",
        comments: [
          "Studentersamfundet, øverste etasje.",
          "KODE café hvis du tåler litt bakgrunnsstøy.",
        ]
      },
      {
        user: "sofie_regnby", community: "kultur", hours_ago: 18, votes: 6,
        title: "Grieghallen i helgen",
        content: "Skal på Beethoven med Bergen Filharmoniske. Har noen vært der nylig — hvor tidlig bør man være inne?",
        image: "bergen-concert-hall", comments: [
          "30 min før er plenty.",
          "Husk at garderoben kan ta tid på fulle dager.",
        ]
      },
      {
        user: "anders_fisketorget", community: "mat", hours_ago: 20, votes: 5,
        title: "Fisketorget lørdag — hva kjøper dere?",
        content: "Reker, blåskjell og litt laks hver gang. Finnes det noe lokalt jeg alltid overser?",
        image: "bergen-fish-market", comments: [
          "Kveite om de har det.",
          "Spør om hummersuppe-restene, billig og godt.",
        ]
      },
      {
        user: "marte_kode24", community: "bergen", hours_ago: 22, votes: 6,
        title: "Tech-meetup på Mesh?",
        content: "Så at det er meetup på Mesh neste uke. Noen her som har vært — er det mer mingling eller foredrag?",
        comments: [
          "Begge deler, avslappet stemning.",
          "Ta med ladekabel, sitteplassene fylles fort.",
        ]
      },
      {
        user: "jonas_7fjell", community: "bergen", hours_ago: 24, votes: 7,
        title: "Damsgårdsfjellet ved solnedgang",
        content: "Løp opp i går kveld — helt rått lys over Puddefjorden. Lokal hemmelighet eller kjenner alle til dette allerede?",
        image: "bergen-damsgardsfjellet", comments: [
          "Kjenner mange til det, men fortjener mer love.",
          "Ta vindjakke, det blåser som regel på toppen.",
        ]
      },
      {
        user: "jonas_7fjell", community: "bergen", hours_ago: 36, votes: 5,
        title: "Løypeforslag for 7-fjellsturen",
        content: "Skal endelig ta 7-fjellsturen i sommer. Vil gjerne dele etappen i to dager — har dere en favorittrute?",
        image: "bergen-hiking", comments: [
          "Dag 1: Fløyen–Rundemanen, dag 2: resten.",
          "Husk nok vann mellom Lyderhorn og Damsgårdsfjellet.",
        ]
      },
      {
        user: "hanne_sandviken", community: "norge", hours_ago: 38, votes: 5,
        title: "Barnehageplass i Bergen — realistisk ventetid?",
        content: "Flytter til Sandviken til høsten. Hva er erfaringen deres med ventelister i bydelen?",
        comments: [
          "Var 4 måneder for oss, avhengig av bydel.",
          "Søk tidlig og følg opp med kommunen.",
        ]
      },
      {
        user: "per_laksevag", community: "bergen", hours_ago: 40, votes: 6,
        title: "Nye sykkelstier langs Store Lungegårdsvann",
        content: "Syklet rundt vannet i går kveld. Nye lys gjør det mye tryggere. Håper de fortsetter mot Puddefjorden.",
        image: "bergen-lungegaardsvann", comments: [
          "Enig, stor forbedring.",
          "Fortsatt litt glatt ved regn, ta det rolig i svingene.",
        ]
      },
      {
        user: "silje_korall", community: "musikk", hours_ago: 44, votes: 8,
        title: "Bergenfest — hvilke artister satser dere på?",
        content: "Lineup er ute og jeg klarer ikke velge én dag. Hvem er must-see i år?",
        comments: [
          "Fredagskvelden ser sterk ut.",
          "Kom tidlig for parken, det blir folksomt.",
        ]
      },
      {
        user: "tor_fana", community: "bergen", hours_ago: 48, votes: 4,
        title: "Vannlekkasje i leilighet — hva gjør man først?",
        content: "Vann fra taket i Fana i natt. Har dokumentert og ringt utleier. Noe mer jeg bør gjøre med en gang?",
        comments: [
          "Ta bilder av alt, også inventar.",
          "Meld til forsikring samme dag.",
        ]
      },
      {
        user: "live_bergenlive", community: "kultur", hours_ago: 52, votes: 5,
        title: "Standup på Logen denne uken",
        content: "Noen som har vært på open mic der? Tenker å teste en kort settliste.",
        image: "bergen-logen", comments: [
          "Hyggelig publikum, kom tidlig.",
          "Book plass, det er begrenset kapasitet.",
        ]
      },
      {
        user: "ola_nordnes", community: "mat", hours_ago: 56, votes: 6,
        title: "Kolonialen brunch — verdt prisen?",
        content: "Vurderer å ta med foreldre dit søndag. Er porsjonene og stemningen like gode som folk sier?",
        image: "bergen-brunch", comments: [
          "Ja, book bord i god tid.",
          "Sitte ute hvis været spiller på lag.",
        ]
      },
      {
        user: "emilie_floyen", community: "bergen", hours_ago: 72, votes: 5, anonymous: true,
        title: "Anonym: nattbuss etter sentrum?",
        content: "Jobber sent på hverdager. Er nattbussene fortsatt upålitelige etter midnatt, eller har det blitt bedre?",
        comments: [
          "Bedre etter ruteendring, men sjekk Boreal-app.",
          "Skyss natt viser sanntid nå.",
        ]
      },
      {
        user: "henrik_vestland", community: "mat", hours_ago: 88, votes: 4,
        title: "Pizza på Nordnes — Deli eller Bella?",
        content: "Klassisk fredagskrangel i kollektivet. Hva vinner i Bergen akkurat nå?",
        comments: [
          "Deli for tynn bunn.",
          "Bella når man vil ha storfamilie-porsjoner.",
        ]
      },
      {
        user: "kari_bybanen", community: "bergen", hours_ago: 96, votes: 7,
        title: "Tåk over Vågen i dag",
        content: "Gikk over Bryggen i tjukk tåke — føltes som en annen by. Tok noen bilder hvis noen vil ha wallpaper.",
        image: "bergen-fog-vagen", comments: [
          "Legg ut!",
          "Perfekt stemning for svart/hvitt.",
        ]
      },
      {
        user: "ola_nordnes", community: "norge", hours_ago: 120, votes: 5,
        title: "Boligpriser i Bergen — fortsatt helt sprøtt?",
        content: "Ser på 2-roms i Møhlenpris. Er det noen som faktisk har kjøpt nylig uten å vinne arv-lotteriet?",
        comments: [
          "Møhlenpris holder seg høyt, sjekk borettslag vs. eier.",
          "Vurder Laksevåg hvis du vil ha bedre kvm-pris.",
        ]
      },
      {
        user: "ingrid_ulriken", community: "bergen", hours_ago: 140, votes: 4,
        title: "Hundepark anbefalinger?",
        content: "Ny hund i familien. Hvor i Bergen er det best å slippe den løs uten å måtte kjøre 40 min?",
        image: "bergen-dog-park", comments: [
          "Nordnesparken tidlig morgen.",
          "Fana fjellstier hvis den tåler mer aktivitet.",
        ]
      },
      {
        user: "sofie_regnby", community: "bergen", hours_ago: 28, votes: 6,
        title: "VilVite med barn — hva er best?",
        content: "Søndagstur med seksåring. Er det noen utstillinger eller show dere alltid prioriterer?",
        comments: [
          "Vitenshowet er gull verdt.",
          "Ta med lunsj, kaféa kan bli full.",
        ]
      },
      {
        user: "anders_fisketorget", community: "bergen", hours_ago: 32, votes: 5,
        title: "Studentersamfundet torsdag — hvem møter?",
        content: "Tenker å dra dit etter jobb for billig øl og quiz. Er det fortsatt god stemning midt i uka?",
        comments: [
          "Quiz starter kl 19, kom tidlig.",
          "Bordene ved vinduet går først.",
        ]
      },
      {
        user: "tor_fana", community: "bergen", hours_ago: 4, votes: 21,
        title: "Brann på Stadion i kveld — hvor ser dere kampen?",
        content: "Fikk ikke billett og vil ikke se den alene. Hvilken pub tar imot Brann-folk uten kø?",
        comments: [
          "Fotballpuben i Nygårdsgaten. Kom en time før avspark.",
          "Bien på Møhlenpris viser alltid, og trykket er høyt.",
        ]
      },
      {
        user: "hanne_sandviken", community: "bergen", hours_ago: 12, votes: 18,
        title: "Leiepriser i Bergen — har de flatet ut?",
        content: "Leter etter toroms under 14 000 nær sentrum. Urealistisk i år, eller finnes det fortsatt?",
        comments: [
          "Let ett stopp ut på Bybanen. Prisen faller fort.",
          "Følg Hybel og Finn daglig. De gode går på timer.",
        ]
      },
      {
        user: "magnus_student", community: "bergen", hours_ago: 30, votes: 15,
        title: "Flyttet til Bergen forrige uke — hva bør jeg vite?",
        content: "Ny jobb, kjenner ingen. Gi meg det ene rådet dere skulle hatt første måneden her.",
        comments: [
          "Kjøp ordentlig regntøy før du kjøper noe annet.",
          "Bli med på en fjelltur. Det er slik folk finner venner her.",
        ]
      },
      {
        user: "henrik_vestland", community: "bergen", hours_ago: 15, votes: 24,
        title: "Dag 18 med regn — teller noen fortsatt?",
        content: "Naboen sier det er sunt. Jeg sier vi bygger ark. Hvordan holder dere humøret oppe i grå uker?",
        comments: [
          "Paraply er for nybegynnere. Skikkelig jakke og godt humør.",
          "Kaffe, bok, vindu mot Vågen. Da blir regnet kulisse.",
        ]
      },
    ].freeze
  end
end
