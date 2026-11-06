// New completion content, November 2026.
// Sources: the operator's pasted archive documents (Ilumild booking page,
// Ragnhilds Begravelsesbyrå tjenestesider og halloween-versjoner, Evighetspartiet
// forretningsplan, Fetat – Familieetaten). Every number comes from those
// documents or from numbers already in the plan; nothing is invented.
// Merge semantics per field: a leading '+' appends to the ported content,
// otherwise the field replaces it. govt_bergen.tech_extra is composed in
// bp_build.mjs because its FETAT facts must land inside the first h3 group.
export const ADDITIONS = {
  ragnhild: {
    tech_extra: `
<h3>Tjenestekatalog og partnere</h3>
<p>Tjenestesidene i arkivene lister katalogen i full bredde, og hver tjeneste har en fast partner som bærer utførelsen. Festbyrået står for Karaokekisten, der stemmeoverføringsteknologi lar den avdødes favorittsanger synges en siste gang; Lysmestrene leverer Diskokistens LED-lys; Latterfabrikken stiller klovne-pallbærerne; Fyrverkeriekspertene synkroniserer det pyrotekniske avskjedsfyrværkeriet mot favorittmusikken. Humorhuset fremfører stand-up-eulogier, Ordsmia skriver poetiske avskjeder, Kistegalskapen bygger sprø kistedesign – kisten som hotdog eller gigantisk sko – og Morrogutta rigger kiste med rutsjebane. Katalogen rommer også romferd, der en andel av asken sendes i bane rundt jorden, musikalsk avskjed med live band eller strykekvartett, og Piratferd i flammene: vikingferd med skjoldvegg og krigstrommer. Partnermodellen holder katalogen skalerbar uten egenproduksjon – byrået selger, koordinerer og kvalitetssikrer, partnerne leverer.</p>
<h3>Søstermerket Ilumild og pakkestrukturen</h3>
<p>Samme bookingplattform bærer to merkevarer. Ragnhild feirer et liv; Ilumild – «Moderne og omsorgsfull begravelsestjeneste» – betjener dem som vil ha ro, bærekraft og tilgjengelighet fremfor innslag. Ilumilds tre pakker utgjør pakkestrukturen: Basis (fra 30 000 kroner) med planlegging og rådgivning, enkel seremoni, digital minneside og enkelt gravsted eller urne; Premium (fra 60 000 kroner) med personlig seremonioppsett, musikk, lys, personlige elementer, transport og koordinering; Deluxe (fra 120 000 kroner) med global VR- eller live-strøm, biodegraderbar kiste eller havbegravelse og minne-tre-planting. Deltakertillegget ligger på 50, 80 og 200 kroner per gjest, og 60-sekunderskalkulatoren gir estimat og pakkeanbefaling før den første samtalen – pristransparensen som skiller begge merkevarene fra kjedenes skjulte prisspill. Tilgjengelighetsmålet er WCAG AA, og konverteringsmålet på henvendelser er 12 prosent eller bedre. Ro-modus-veiviseren leder sjokkerte pårørende steg for steg, minnesiden kan lastes ned som minnebok-PDF, og minne-tre-plantingen fungerer som karbonkompensasjon og samfunnsinnsats.</p>
<h3>Den digitale plattformen</h3>
<p>MVP-en piloteres på to uker: digitalt bestillingsskjema med bekreftelse på e-post og SMS, to pakker live, én gjennomført seremoni med lokal respons og tilbakemelding, og en tilgjengelighetstest mot WCAG AA. Stakken følger samme OpenBSD- og Ruby-tradisjon som MASTER: Ruby on Rails i backend, Hotwire og Stimulus i frontend, OpenBSD på serveren, og et CRM for håndtering av henvendelser og pre-need-kontrakter.</p>
<p>Personvernet er produktkritisk i en sensitiv bransje: all persondata krypteres i hvile og under overføring, tilgangen begrenses til autorisert personell, og databehandleravtaler tegnes før drift. Seremoniteknologien har offline-plan som fallback, dobbelte strømsystemer og reserveutstyr i bilen. Kremasjon og logistikk utføres i samarbeid med autoriserte gravferdsentreprenører, og juridisk gjennomgang av gravferdsregelverket følges før lansering i hver kommune. Den grønne profilen er standard i premium-pakkene – biodegraderbare kister, treplanting og lavkarbo-alternativer – og en andel av overskuddet går til sorgstøttetiltak i lokalsamfunnet, som ledd i å rydde bransjen for svart økonomi.</p>
`,
    'gomarket': `+
<h3>Merkevare og kanal</h3>
<p>Ragnhild selv er kanalen: verdens første begravelses-influencer med over to millioner følgere, som viser frem kistemoder og #EtterLivMålene siden livesendingen som startet alt. Merkevarehistorien bærer katalogen: flukten fra Norge etter en katastrofal karaokekveld, årene på vandring med ABBA som fast følgesvenn, og returen til et eget byrå der mørk humor fra stand-up-scenen møter seremoniell respekt. Signaturen «Vi tar vare på deg, selv når du ikke lenger tar vare på deg selv» leder all kommunikasjon, og halloween-versjonene i arkivene gjør halloween til en årlig kampanjearena – «Happy Halloween, you freaks» – der katalogens villste tjenester får spille, med respektens grenser intakt resten av året.</p>
`,
    'ekstern': `+
<p>Plattformsiden krever dessuten GDPR-rådgivning og databehandleravtaler før første bestilling, og autoriserte gravferdsentreprenører knyttes til som driftspartnere for kremasjon og logistikk i hver by.</p>
`,
    logo: {
      kind: 'font',
      text: 'Ragnhilds',
      font: 'Nosifer',
      note: 'Logo: «Ragnhilds»-ordmerket satt i Nosifer (SIL Open Font License), dråpefonten fra halloween-versjonene i arkivene – her i statisk gjengivelse.',
    },
  },

  govt_bergen: {
    'why_now': `+
<h3>Visjon, misjon og verdier</h3>
<p>Bevegelsen bak plattformen heter Bergens Selvstyrepartiet; arkivene lanserte den også under navnet Evighetspartiet, med mottoet «Frihet, autonomi, transparens». Visjonen er en selvstyrt og autonom Bergen der innbyggerne deltar i beslutningsprosessene og får direkte innflytelse på hvordan byen styres. Misjonen er å redusere byråkrati, gi makten tilbake til folket og etablere et styresett med frihet, autonomi og rettferdighet i sentrum. Fem kjerneverdier bærer arbeidet: transparens, deltakelse, lokal autonomi, bærekraft og digital innovasjon.</p>
`,
    'kundeinnsikt': `+
<h3>Politisk landskap</h3>
<p>Bevegelsens analyse fra lanseringsfasen målte etterspørselen etter et nytt lokalt alternativ: 60 prosent av bergenserne ønsker mer direkte demokrati, 45 prosent er misfornøyde med det byråkratiske systemet, 70 prosent støtter økt lokal autonomi fra Oslo, og 80 prosent ønsker mer transparent styring. Tallene peker mot samme konklusjon som Årstad-piloten: involvering vinner når innvirkningen er reell, og transparensen er selv produktet.</p>
`,
    'gomarket': `+
<h3>Politisk plattform</h3>
<p>Plattformsaken ligger i partiets hovedprogram som fem saker: full autonomi for Bergen kommune, direkte demokrati med folkeavstemninger om viktige saker, grønn omstilling med karbonnøytral by innen 2030, boligpolitikk som gir rimelige boliger til alle bergensere, og næringslivspolitikk som støtter lokale bedrifter og startups. Sakslisten er også salgsargumentet: hver sak gir plattformen en konkret brukssak, fra åpne budsjettvedtak til boligsaken, slik at valgprogrammet og produktet validerer hverandre.</p>
`,
    'milestones': `+
<h3>Bevegelsens faser</h3>
<p>Partiet driver i tre faser som løper foran plattformens milepæler. Mobiliseringen (0–6 måneder) bygger grasrotbevegelsen, etablerer den digitale plattformen og rekrutterer kandidater. Valgkampen (6–12 måneder) lanserer det politiske programmet, gjennomfører folkemøter og bygger allianser. Implementeringen (12 måneder og frem) vinner lokalvalget, implementerer reformene og etablerer den nye styringsmodellen – med lokalvalget 2027 som fullskalapilot for både parti og plattform.</p>
`,
    'likviditet': `+
<h3>Bevegelsens finansiering</h3>
<p>Partisiden samler NOK 10 millioner til de første fasene, fordelt på fire kilder:</p>
<table class="numbers">
<caption>Bevegelsens finansiering, NOK millioner</caption>
<thead><tr><th>Kilde</th><th>Beløp</th></tr></thead>
<tbody>
<tr><td>Private donasjoner</td><td>4,0</td></tr>
<tr><td>Crowdfunding</td><td>3,0</td></tr>
<tr><td>Medlemskontingent</td><td>2,0</td></tr>
<tr><td>Arrangementer</td><td>1,0</td></tr>
</tbody>
<tfoot><tr><td>Samlet mål</td><td>10,0</td></tr></tfoot>
</table>
<p>Medlemskontingenten og arrangementene er gjentakende inntekter som dekker den løpende kampanjedriften; donasjonene og crowdfundingen finansierer plattformutviklingen. Partifinansieringen holdes adskilt fra selskapets budsjetter – partiet eier saken, selskapet leverer plattformen.</p>
`,
    // Tech additions, composed against the ported block in bp_build.mjs:
    // FETAT facts land after the Plattformforslag 1 paragraph, the third
    // proposal appends at the end of the section.
    tech_extra_fetat: `
<p>Faktagrunnlaget fra FETAT-heftet: Norge er felt i Den europeiske menneskerettsdomstolen 24 ganger for brudd på EMK artikkel 8, retten til familieliv – på ingen andre områder har Norge flere fellelser – og barnevernet koster samfunnet 26 milliarder kroner årlig fordelt på 356 kommuner. Vilkårligheten er målt: klageinstansene ga 3 prosent medhold på akuttvedtak i Trøndelag og 35 prosent i Oslo, og standardisert samværspraksis på 2–6 årlige samvær «sementerer situasjonen» i stedet for å bevare familiebånd. NOU 2023:7 oppsummerer systemet: «Et system med svakheter i kompetanse, prioritering, struktur og tilsyn. Et system som åpner for vilkårlighet.»</p>
<p>Heftets fire pilarer – gjenforeningsfokus fra dag én, tverrfaglige team etter Barnahús-modellen, tidlig familiestøtte før krisen eskalerer, og kvalitetssikring som dokumenterer barnets stemme – fordeler seg over de samme prinsippene.</p>
<table class="numbers">
<caption>FETAT: forventet effekt</caption>
<thead><tr><th>Indikator</th><th>Mål</th></tr></thead>
<tbody>
<tr><td>Reduksjon i unødvendige omsorgsovertakelser</td><td>30 %</td></tr>
<tr><td>Økning i vellykkede tilbakeføringer</td><td>50 %</td></tr>
<tr><td>EMD-fellelser for deltakende kommuner</td><td>0</td></tr>
<tr><td>Årlig samfunnsbesparelse ved 50 kommuner</td><td>400 mill. kr</td></tr>
</tbody>
</table>
<table>
<caption>FETAT: implementering</caption>
<thead><tr><th>Fase</th><th>Tidsrom</th><th>Innhold</th></tr></thead>
<tbody>
<tr><td>Pilot</td><td>2026</td><td>3 kommuner, metodikkutvikling, forskningssamarbeid</td></tr>
<tr><td>Validering</td><td>2027</td><td>12 måneder drift, uavhengig evaluering, justering</td></tr>
<tr><td>Skalering</td><td>2028–2030</td><td>Utvidelse til 50 kommuner, regional struktur</td></tr>
</tbody>
</table>
<p>Hva som kreves: politisk vilje på kommunalt og nasjonalt nivå, lovhjemmel for alternative organiseringsformer, pilotkommuner som går foran, og forskningssamarbeid for uavhengig evaluering. Norge kan ikke fortsette å tape i Strasbourg; FETAT tilbyr veien ut – et barnevern som beskytter barn og respekterer familiers grunnleggende rettigheter. Dokumentet står som eget hefte i arkivet (STUDIO/docs/fetat/proposal.md) og kontakteres på fetat.no og post@fetat.no.</p>
`,
    tech_extra_forslag3: `
<h3>Plattformforslag 3: parametrisk arkitektur og Bergen-coin</h3>
<p>Partiprogrammet strekker forvaltningsteknologien ut i to satsinger som bygger på samme tillitsinfrastruktur. Parametrisk arkitektur skal gi bærekraftige og fleksible bygg i Bergen: adaptiv design som tilpasser seg klimaendringer og befolkningsvekst, slik at kommunale bygg følger bruk og vær i stedet for å låses i statiske planer. Bergen-coin er forslaget om lokal kryptovaluta for lokal økonomi, under samme transparenskrav som resten av plattformen: åpen kildekode, offentlig hovedbok og smarte kontrakter som automatiserer tjenesteleveranser og kutter byråkratiske mellomledd. Det transparente budsjettet hører samme sted hjemme: alle kommunale utgifter legges åpent, i åpen kildekode, slik at hver innbygger kan følge kronene fra vedtak til leveranse.</p>
`,
    'ekstern': `+
<p>Bevegelsesfasen legger til valgkamp- og mediekompetanse, folkemøteorganisering og rådgivning på partifinansieringsregelverket.</p>
`,
  },
};
