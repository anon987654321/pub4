#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate HTU-layout legat letters + manifest for grok/mutt automation.
# Canonical economics: funding.yml
require "yaml"
require "fileutils"
require_relative "funding_helpers"
require_relative "lib/bplan/constants"
require_relative "lib/bplan/html"
require_relative "lib/bplan/validate"

ROOT = File.expand_path(__dir__)
FUNDING = FundingHelpers.load_funding(ROOT)
LEGATS_DIR = File.join(ROOT, "legats")
HTU_CSS = "../#{Bplan::Constants::HTU_CSS}"
LOGO = "../#{Bplan::Constants::LOGO}"
DATE = Bplan::Constants::DATE
DATE_ISO = Bplan::Constants::DATE_ISO
APPLICANT = Bplan::Constants::APPLICANT

def wrap_letter(title:, meta:, body:, outfile:, description: nil, funder_id: nil, footer_name: APPLICANT[:footer])
  html = Bplan::Html.wrap_letter(
    title: title,
    description: description || "#{title} — #{meta.gsub('<br>', ' ')}",
    meta: meta,
    body: body,
    funder_id: funder_id,
    css_href: HTU_CSS,
    logo_src: LOGO,
    footer_name: footer_name,
  )

  path = File.join(LEGATS_DIR, outfile)
  File.write(path, html)
  puts "wrote legats/#{outfile}"
  path
end

def funder_record_for(app)
  if app[:funder_id]
    return FUNDING["funders"].find { |f| f["id"] == app[:funder_id].to_s }
  end

  needle = app[:funder].to_s.downcase[0, 24]
  FUNDING["funders"].find { |f| f["name"].to_s.downcase.include?(needle) || needle.include?(f["id"].to_s) }
end

def manifest_sendable?(app, funder_record)
  return false if app[:draft]
  return false if app[:to] == APPLICANT[:email]
  return false if app[:file].to_s.start_with?("vx_")
  return false if app[:low_priority]
  return false if Bplan::Constants::NON_SENDABLE_APP_FILES.include?(app[:file].to_s)
  return false if funder_record&.dig("portal_only")

  true
end

def manifest_notes(app, funder_record)
  Bplan::Constants::NON_SENDABLE_NOTES[app[:file].to_s] ||
    if funder_record&.dig("portal_only")
      "Portal/skjema-kanal (#{funder_record['preferred_channel'] || 'portal'}) — ikke auto-e-post. Bekreft på contact_url."
    else
      "Bekreft mottakeradresse på contact_url før mutt-sending."
    end
end

def applicant_meta(funder:, extra: nil)
  parts = [
    funder,
    "#{APPLICANT[:org]} · #{APPLICANT[:address]}",
    extra,
    "<time datetime=\"#{DATE_ISO}\">#{DATE}</time>",
  ].compact
  parts.join("<br>")
end

def standard_sections(project:, deliverables:, angle:, funder_type: :legat, funder_id: nil, **_legacy)
  FundingHelpers.letter_sections(
    project: project,
    deliverables: deliverables,
    angle: angle,
    funding: FUNDING,
    funder_type: funder_type,
    funder_id: funder_id,
  )
end

FileUtils.mkdir_p(LEGATS_DIR)

# Each entry: filename, title, funder, meta_extra, body, manifest fields
applications = []

def add_app(apps, **entry)
  apps << entry
end

# --- Major innovation / health funders ---

add_app applications,
  file: "01_innovasjon_norge_master.html",
  title: "Søknad — Innovasjonskontrakt",
  funder: "Innovasjon Norge",
  to: "post@innovasjonnorge.no",
  subject: "Søknad: MASTER — selvforbedrende AI-plattform for helseteknologi",
  contact_url: "https://www.innovasjonnorge.no",
  deadline: "Fortløpende — avtal med rådgiver Bergen",
  track: "innovasjon",
  project: "master",
  funder_id: "innovasjon_norge",
  body: standard_sections(
    project: "master",
    funder_type: :innovasjon,
    funder_id: "innovasjon_norge",
    angle: "Innovasjon Norge passer fordi prosjektet kombinerer produkt- og prosessinnovasjon med tydelig markedspotensial og behov for pilotkunde i helse/velferd.",
    deliverables: [
      "Modnet MASTER-kjerne med dokumentert selvforbedringsløkke",
      "To pilotklare RAILS-apper for helsearbeidsflyt",
      "Innovasjonskontrakt med norsk pilotkunde",
      "Kommersialiseringsplan for PubHealthcare",
    ]
  )

add_app applications,
  file: "02_trond_mohn_medical_ai.html",
  title: "Søknad — Medisinsk kunstig intelligens",
  funder: "Trond Mohn Foundation",
  to: "post@mohnfoundation.no",
  subject: "Pre-kvalifisering: MASTER + pub.healthcare for medisinsk AI",
  contact_url: "https://mohnfoundation.no",
  deadline: "Se mohnfoundation.no — to-trinnsprosess med UiB/Helse Bergen",
  track: "helse",
  project: "master+pub.healthcare",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Jeg søker støtte til utvikling av medisinsk relevante AI-verktøy basert på MASTER-arkitekturen og pub.healthcare sine Rails-applikasjoner. Prosjektet kan styrke koordinering og informasjon (ikke diagnose), simulering og effektivisering i kliniske arbeidsflyter — med norsk kontroll over data og kode.</p>
    <p>#{FundingHelpers::MASTER_BLURB}</p>

    <h2>2. Klinisk relevans</h2>
    <p>Helse Bergen og UiB samarbeider allerede i TMF-utlysninger om medisinsk AI. Dette prosjektet tilbyr en konkret teknologiplattform for trygg, sporbar og selvkorrigerende programvareutvikling — med applikasjoner som kan testes i pasientnære og administrative sammenhenger.</p>

    <h2>3. Samarbeidsbehov</h2>
    <p>Jeg søker dialog med relevante fagmiljø ved Det medisinske fakultet, UiB og Helse Bergen for felles pre-kvalifisering. MASTER leverer teknologikjernen; kliniske partnere validerer use cases.</p>

    <h2>4. Leveranser</h2>
    <ul>
      <li>MASTER-drevet utviklingsplattform for medisinsk programvare</li>
      <li>pub.healthcare-prototyper for koordinering og informasjon (ikke diagnose)</li>
      <li>Sikkerhets- og etikkdokumentasjon (OpenBSD-modell, konstitusjonelle prinsipper)</li>
      <li>Pilotplan med målbare kliniske eller administrative effekter</li>
    </ul>

    <h2>5. Budsjett</h2>
    <p><strong>Mål:</strong> #{FundingHelpers.innovasjon_ask_text("pub_healthcare", FUNDING, funder_id: "trond_mohn")} over 12–18 måneder med UiB/Helse Bergen-partner.</p>
    <p class="meta">Pre-kvalifisering kreves — ikke søk millionbeløp uten klinisk samarbeid.</p>
  BODY

add_app applications,
  file: "03_helse_vest_velferdsteknologi.html",
  title: "Søknad — Velferdsteknologi og pasientnære tjenester",
  funder: "Helse Vest RHF",
  to: "post@helse-vest.no",
  subject: "Søknad: MASTER/RAILS — velferdsteknologi for Vestland",
  contact_url: "https://www.helse-vest.no",
  deadline: "Se helse-vest.no innovasjonsutlysninger",
  track: "helse",
  project: "pub_healthcare",
  funder_id: "helse_vest",
  body: standard_sections(
    project: "pub_healthcare",
    funder_type: :innovasjon,
    funder_id: "helse_vest",
    angle: "Velferdsteknologi handler om trygghet, selvstendighet og ressursutnyttelse — ikke teknologi for teknologiens skyld. RAILS-appene er den praktiske manifestasjonen av MASTERs evner.",
    deliverables: [
      "Prototyp for pasient/pårørende-samhandling (brgen.no-infrastruktur)",
      "Redusert administrativ byrde for helsepersonell",
      "WCAG- og personvern-gjennomgått pilot",
      "Evalueringsrapport fra Vestland-pilot",
    ]
  )

add_app applications,
  file: "04_forskningsradet_ikt_ai.html",
  title: "Søknad — Selvforbedrende AI-systemer",
  funder: "Forskningsrådet",
  to: "post@forskningsradet.no",
  subject: "Søknad: Konstitusjonell, selvforbedrende AI for programvareutvikling",
  contact_url: "https://www.forskningsradet.no",
  deadline: "Se utlysninger IKT og digitalisering",
  track: "forskning",
  project: "master",
  body: standard_sections(
    project: "master",
    funder_type: :forskning,
    funder_id: "forskningsradet",
    angle: "Forskningsvinkelen: hvordan kan selvforbedrende LLM-agenter operere pålitelig innenfor konstitusjonelle rammer, med målbar kvalitetsforbedring over iterative løkker?",
    deliverables: [
      "Publiserbar metodikk for konstitusjonell AI-styring",
      "Empiriske data fra selvforbedringsløkker med målbare kvalitetsforbedringer",
      "Sikkerhetsmodell med OpenBSD pledge/capsicum-inspirasjon",
      "Åpen dokumentasjon for norsk AI-forskningsmiljø",
    ]
  )

add_app applications,
  file: "05_sparebankstiftelsen_sr_bank.html",
  title: "Søknad — Regional innovasjon og samfunnsnytte",
  funder: "Sparebankstiftelsen SR-Bank",
  to: "post@srstiftelsen.no",
  subject: "Søknad: MASTER/RAILS — teknologisk entreprenørskap i Bergen",
  contact_url: "https://srstiftelsen.no",
  deadline: "Fortløpende — søk via srstiftelsen.no",
  track: "regional",
  project: "pub4",
  body: standard_sections(
    project: "master",
    funder_type: :legat,
    funder_id: "sr_bank",
    angle: "SR-Bank støtter tiltak som skaper verdi for regionen. pub4 demonstrerer at avansert AI-utvikling kan skje i Bergen med reelle applikasjoner og arbeidsplasser.",
    deliverables: [
      "Lokal kompetansebygging innen AI og Rails",
      "Synlige prototyper for bergensere (brgen.no)",
      "Dokumentasjon for andre gründere",
      "Åpen kildekode der lisens tillater",
    ]
  )

add_app applications,
  file: "06_vestland_fylke_digitalisering.html",
  title: "Søknad — Digital kompetanse og innovasjon",
  funder: "Vestland fylkeskommune",
  to: "post@vestlandfylke.no",
  subject: "Søknad: MASTER/RAILS — digital verdiskaping i Vestland",
  contact_url: "https://www.vestlandfylke.no/tilskot/",
  deadline: "Se vestlandfylke.no tilskuddsordninger",
  track: "regional",
  project: "pub4",
  body: standard_sections(
    project: "brgen",
    funder_type: :innovasjon,
    funder_id: "vestland_fylke",
    angle: "Fylkeskommunen investerer i regional utvikling. MASTER gjør det mulig for små miljøer å levere digital kvalitet på nivå med større aktører.",
    deliverables: [
      "Workshop-serie om ansvarlig AI-utvikling",
      "Pilot med videregående eller fagskole (åpent API)",
      "Dokumentert metode for sikker app-utvikling",
      "RAILS-demo for offentlig sektor",
    ]
  )

add_app applications,
  file: "07_skattefunn_rnd.html",
  title: "Søknad — SkatteFUNN FoU-prosjekt",
  funder: "SkatteFUNN / Forskningsrådet",
  to: "skattefunn@forskningsradet.no",
  subject: "Søknad SkatteFUNN: Selvforbedrende AI-plattform MASTER",
  contact_url: "https://www.skattefunn.no",
  deadline: "Løpende innsending",
  track: "innovasjon",
  project: "master",
  body: standard_sections(
    project: "master",
    funder_type: :skattefunn,
    funder_id: "skattefunn",
    angle: "SkatteFUNN dekker systematisk forsknings- og utviklingsarbeid. MASTERs selvforbedringsløkker er dokumentert FoU med målbare iterasjoner.",
    deliverables: [
      "FoU-logg med iterasjonsdata",
      "Teknisk rapport per utviklingssyklus",
      "Patent-/IP-vurdering av unike metoder",
      "Produktisert RAILS-applikasjon som FoU-resultat",
    ]
  )

add_app applications,
  file: "08_nordic_innovation_health.html",
  title: "Søknad — Nordisk helseteknologi",
  funder: "Nordic Innovation",
  to: "info@nordicinnovation.org",
  subject: "Søknad: Nordic health tech — MASTER/RAILS from Norway",
  contact_url: "https://www.nordicinnovation.org",
  deadline: "Se nordicinnovation.org utlysninger",
  track: "nordic",
  project: "pub.healthcare",
  body: standard_sections(
    project: "pub_healthcare",
    funder_type: :innovasjon,
    angle: "Nordisk merverdi: norsk sikkerhetsarkitektur + skalerbare Rails-apper kan samarbeide med svenske/danske kliniske partnere.",
    deliverables: [
      "Felles nordisk pilotplan",
      "Delt teknisk dokumentasjon på engelsk og norsk",
      "Interoperabilitetstest med nordisk helse-API",
      "Konferansepresentasjon av resultater",
    ]
  )

# --- Bergen legats (stipendportalen / legathåndboken) ---

add_app applications,
  file: "09_bergen_bys_utdanningsstiftelse.html",
  title: "Søknad — Høyere utdanning og kompetanse",
  funder: "Bergen bys Utdanningsstiftelse",
  to: "postmottak@bergen.kommune.no",
  subject: "Søknad Bergen bys Utdanningsstiftelse 2026 — AI/systemutvikling",
  contact_url: "https://stipendportalen.no/utlysing/4990",
  deadline: "30.09.2026",
  track: "utdanning",
  project: "master",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Jeg søker støtte til høyere kompetanseutvikling innen avansert AI-systemarkitektur og sikker programvareutvikling, med bosted i Bergen. Studie-/prosjektarbeidet er direkte knyttet til MASTER og RAILS — praktisk, dokumentert utvikling med samfunnsnytte.</p>

    <h2>2. Formål</h2>
    <p>Bergen bys Utdanningsstiftelse støtter bergensere i høyere utdanning. Mitt arbeid med pub4/MASTER representerer dybdelæring på tvers av AI, sikkerhet, Ruby/Rails og helseteknologi — fag som Norge trenger flere utøvere av.</p>

    <h2>3. Bruk av midler</h2>
    <table>
      <tr><td>1.</td><td>Kurs, konferanser og faglitteratur (AI, sikkerhet, helse-IT)</td></tr>
      <tr><td>2.</td><td>Nødvendig utstyr for utvikling og dokumentasjon</td></tr>
      <tr><td>3.</td><td>Reise til relevante fagmiljø (UiB, Helse Bergen, Oslo)</td></tr>
    </table>
    <p class="meta"><strong>Søkt:</strong> #{FundingHelpers.legat_ask_text("master", FUNDING)}</p>

    <h2>4. Dokumentasjon</h2>
    <p>Jeg leverer rapport over bruk av støtte og studieprogresjon i tråd med stiftelsens krav.</p>
  BODY

add_app applications,
  file: "10_gunvor_mindes_legat.html",
  title: "Søknad — Gunvor Mindes legat 2026",
  funder: "Gunvor Mindes stiftelse",
  to: "postmottak@bergen.kommune.no",
  subject: "Søknad Gunvor Mindes legat 2026 — utdanning og nødhjelp",
  contact_url: "https://stipendportalen.no/utlysing/4974",
  deadline: "20.09.2026",
  track: "bolig",
  project: "personal",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Jeg søker Gunvor Mindes legat for utdanning og økonomisk støtte i en krevende livssituasjon. Jeg er bosatt i Bergen og arbeider med legitim teknologiutvikling (MASTER/RAILS/pub.healthcare) som kan skape varig inntekt — men trenger brofinansiering nå.</p>

    <h2>2. Økonomisk situasjon</h2>
    <p>Jeg opplever økonomiske vansker knyttet til bolig, utviklingsarbeid uten løpende inntekt og høye levekostnader i Bergen. Støtte vil gå til husleie, nødvendig utstyr og stabilisering — ikke til urelaterte formål.</p>
    #{FundingHelpers.personal_use_of_funds_block(FUNDING)}

    <h2>4. Utdannings- og kompetanseplan</h2>
    <p>Parallelt fullfører jeg kompetanseheving innen AI, helseteknologi og sikker programvareutvikling. Dette er dokumentert arbeid med reelle leveranser (pub.healthcare, brgen.no).</p>

    <h2>5. Påstander</h2>
    <table>
      <tr><td>1.</td><td>Støtte brukes til godkjente formål med kvitteringsdokumentasjon.</td></tr>
      <tr><td>2.</td><td>Jeg er folkeregistrert i Bergen.</td></tr>
      <tr><td>3.</td><td>Søknaden er ærlig og fullstendig.</td></tr>
    </table>
  BODY

add_app applications,
  file: "11_bergen_bys_vanskeligstilte.html",
  title: "Søknad — Økonomisk bistand",
  funder: "Bergen bys stiftelse til økonomisk vanskeligstilte",
  to: "postmottak@bergen.kommune.no",
  subject: "Søknad Bergen bys stiftelse — økonomisk bistand",
  contact_url: "https://stipendportalen.no/organisasjon/1152",
  deadline: "Årlig — søk via Bergen kommune",
  track: "bolig",
  project: "personal",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Jeg søker økonomisk bistand fra Bergen bys stiftelse til økonomisk vanskeligstilte. Jeg er bosatt i Bergen kommune (minst 3 år) og opplever varig økonomisk press — særlig knyttet til bolig og grunnleggende levekostnader.</p>

    <h2>2. Situasjon</h2>
    <p>Som enkeltperson uten stabil lønnsinntekt, men med pågående innovasjonsarbeid, faller jeg mellom stolene i ordinære støtteordninger. Stiftelsen er riktig kanal for ærlig, direkte bistand til vanskeligstilte bergensere.</p>

    #{FundingHelpers.personal_use_of_funds_block(FUNDING)}

    <h2>4. Boligplan</h2>
    <p>Parallelt søker jeg Startlån og boligtilskudd via Bergen kommune Boligkontoret for å kjøpe leilighet — dette er separat spor, men relatert til ønsket om varig stabil boligsituasjon.</p>
  BODY

add_app applications,
  file: "12_bergen_startlan_boligtilskudd.html",
  title: "Søknad — Startlån og boligtilskudd",
  funder: "Bergen kommune Boligkontoret",
  to: "boligkontoret@bergen.kommune.no",
  subject: "Søknad Startlån og boligtilskudd — kjøp av leilighet i Bergen",
  contact_url: "https://www.bergen.kommune.no/bolig",
  deadline: "Fortløpende",
  track: "bolig",
  project: "personal",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Jeg søker Startlån og eventuelt boligtilskudd for å kjøpe leilighet i Bergen. Ordningen er riktig kanal for personer som har vanskelig for å få tilstrekkelig ordinær finansiering, men som kvalifiserer etter kommunens kriterier.</p>

    <h2>2. Bakgrunn</h2>
    <p>Jeg er fast bosatt i Bergen og ønsker varig eierskap til modest bolig i kommunen. Inntekt kommer fra enkeltpersonforetak og innovasjonsprosjekter — noe banker vurderer som ustabil inntekt.</p>

    #{FundingHelpers.boligpakke_block(FUNDING)}

    <h2>4. Påstander</h2>
    <table>
      <tr><td>1.</td><td>Jeg oppfyller bokostnadskrav i Bergen kommune.</td></tr>
      <tr><td>2.</td><td>Boligen skal brukes til egen beboelse.</td></tr>
      <tr><td>3.</td><td>Søknaden er ærlig og fullstendig.</td></tr>
    </table>
  BODY

add_app applications,
  file: "13_westfal_larsen_rederi.html",
  title: "Søknad — Maritim utdanning og digitalisering",
  funder: "Skibsreder H. Westfal-Larsens fond",
  to: "postmottak@bergen.kommune.no",
  subject: "Søknad Westfal-Larsens fond — digital kompetanse for rederinæringen",
  contact_url: "https://stipendportalen.no/organisasjon/2158",
  deadline: "Se fondets vedtekter",
  track: "utdanning",
  project: "bsdports",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Jeg søker støtte til kompetanseutvikling som binder Bergen, maritim næring og sikker programvare sammen. bsdports.org — en RAILS-app under MASTER — kartlegger og sikrer open source-pakker på OpenBSD, direkte relevant for robust skipssystemer og havnerelasjonert IT.</p>

    <h2>2. Knytning til rederinæring</h2>
    <p>Bergen er Norges maritime hovedstad. Digital sikkerhet ombord og i landbaserte systemer krever minimal-privilege-arkitektur — nøyaktig det bsdports og MASTER adresserer.</p>

    <h2>3. Plan</h2>
    <ul>
      <li>Praksis/studieopphold knyttet til maritim IT-sikkerhet</li>
      <li>Utvidelse av bsdports med maritime avhengighetsanalyser</li>
      <li>Rapport til fondets styre</li>
    </ul>
    #{FundingHelpers.legat_budget_section("bsdports", FUNDING)}
  BODY

add_app applications,
  file: "14_anthonstiftelsen_ungdom.html",
  title: "Søknad — Teknologi for barn og unge",
  funder: "Anthonstiftelsen",
  to: "post@anthonstiftelsen.no",
  subject: "Søknad: MASTER/RAILS — digital kompetanse for ungdom i Bergen",
  contact_url: "https://stipendportalen.no/anthonstiftelsen",
  deadline: "Fortløpende",
  track: "sosial",
  project: "brgen",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Jeg søker støtte til et prosjekt som gir bergenske ungdommer trygg, åpen tilgang til digital demokratisk deltakelse via brgen.no — bygget med MASTER og RAILS.</p>

    <h2>2. Formål</h2>
    <p>Anthonstiftelsen støtter barn og unge. Dette prosjektet lærer ungdom å forstå algoritmer, identitet på nett og lokal demokratisk deltakelse — med MASTER som pedagogisk demonstrator for ansvarlig AI.</p>

    <h2>3. Workshop-plan (dokumentert)</h2>
    <table>
      <tr><td>1.</td><td>Uke 1–2: «Hva er algoritmen?» — kritisk tenkning og kildekritikk</td></tr>
      <tr><td>2.</td><td>Uke 3–4: Trygg identitet på nett — Vipps/Google, passord, phishing</td></tr>
      <tr><td>3.</td><td>Uke 5–6: Lokal demokrati — brgen.no pilot per bydel</td></tr>
      <tr><td>4.</td><td>Uke 7–8: MASTER-demo — ansvarlig AI uten hype</td></tr>
    </table>
    <h2>4. Leveranser</h2>
    <ul>
      <li>8 åpne workshop-økter i Bergen</li>
      <li>WCAG 2.2 AA-mål dokumentasjon på klart norsk</li>
      <li>Rapport til Anthonstiftelsen</li>
    </ul>
  BODY

# --- Per RAILS app / business line ---

add_app applications,
  file: "15_master_kjerne_direkte.html",
  title: "Søknad — MASTER kjerneplattform",
  funder: "Generell innovasjon / teknologi",
  to: APPLICANT[:email],
  subject: "Søknad: MASTER — direkte kjerneplattform for selvforbedrende AI",
  contact_url: "https://stipendportalen.no/stotteordninger",
  deadline: "Tilpass per giver",
  track: "innovasjon",
  project: "master",
  body: standard_sections(
    project: "master",
    angle: "Direkte MASTER-søknad uten indirekte vinkel: fokus på konstitusjonell styring, multi-agent council, selvrefinering og sikkerhet.",
    deliverables: [
      "Stabilisert MASTER-kjerne med 10-trinns pipeline",
      "Dokumentert selvforbedringsløkke med målbare resultater",
      "OpenBSD-kompatibelt kjøremiljø",
      "CRDT-konvergens og kostnadskontroll",
    ]
  )

add_app applications,
  file: "16_brgen_digitalt_demokrati.html",
  title: "Søknad — brgen.no samfunnsplattform",
  funder: "Demokrati og medieteknologi",
  to: APPLICANT[:email],
  subject: "Søknad: brgen.no — hyperlokalt digitalt demokrati i Bergen",
  contact_url: "https://stipendportalen.no",
  deadline: "Tilpass per giver",
  track: "samfunn",
  project: "brgen",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>brgen.no er en Rails 8-samfunnplattform med bydelsmedia, markedsplass, fellesskapsverktøy og mer — utviklet og forbedret av MASTER. Den styrker lokalt fellesskap, tillit og digital deltakelse.</p>
    <p>#{FundingHelpers::MASTER_BLURB}</p>

    <h2>2. Samfunnsnytte</h2>
    <p>Verdiskaping for fellesskapet: trygg identitet (Vipps/Google OAuth), moderering, tillitssignaler og åpen aktivitetsgraf. Dette er velferdsteknologi for det sivile samfunn.</p>

    <h2>3. Leveranser</h2>
    <ul>
      <li>Pilot i tre bergenske bydeler</li>
      <li>MASTER-drevet innholdsmoderering og tilgjengelighet</li>
      <li>Åpent API for forskning og journalistikk</li>
    </ul>

    <h2>4. Budsjett</h2>
    <p><strong>Søkt:</strong> #{FundingHelpers.legat_ask_text("brgen", FUNDING)} · <strong>IN-mål:</strong> #{FundingHelpers.innovasjon_ask_text("brgen", FUNDING)} for MVP-pilot 12 måneder.</p>
  BODY

add_app applications,
  file: "17_amber_baerekraft_mote.html",
  title: "Søknad — Amber bærekraftig mote",
  funder: "Bærekraft og innovasjon",
  to: APPLICANT[:email],
  subject: "Søknad: amber.brgen.no — bærekraftig garderobe og sirkulær mote",
  contact_url: "https://stipendportalen.no",
  deadline: "Tilpass per giver",
  track: "klima",
  project: "amber",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>amber.brgen.no er en Rails-app for garderobeforvaltning, kost-per-bruk-analyse, outfit-generering og sirkulær mote — utviklet med MASTER.</p>

    <h2>2. Bærekraft</h2>
    <p>Overforbruk av klær belaster klima og ressurser. Amber hjelper brukere å bruke det de har, redusere impulskjøp og forlenge levetiden til plagg — velferdsteknologi for forbrukerøkonomi og miljø.</p>

    <h2>3. Innovasjon</h2>
    <ul>
      <li>AI-drevet outfit-forslag etter vær og anledning</li>
      <li>Segmentering og bakgrunnsfjerning for digital garderobe</li>
      <li>Sosial deling uten kommersiell overstyring</li>
    </ul>
  BODY

add_app applications,
  file: "18_bsdports_digital_suverenitet.html",
  title: "Søknad — bsdports.org sikker programvare",
  funder: "Digital suverenitet og sikkerhet",
  to: APPLICANT[:email],
  subject: "Søknad: bsdports.org — norsk sikker pakkeinfrastruktur",
  contact_url: "https://stipendportalen.no",
  deadline: "Tilpass per giver",
  track: "sikkerhet",
  project: "bsdports",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>bsdports.org kartlegger OpenBSD-porter, avhengigheter og sårbarheter — en RAILS-app bygget med MASTER. Reduserer avhengighet av utenlandsk lukket infrastruktur.</p>

    <h2>2. Samfunnsnytte</h2>
    <p>Offentlig sektor og kritisk infrastruktur trenger sporbar, sikker programvare. bsdports gjør pakkeøkosystemet søkbart, forståelig og revisjonert.</p>

    <h2>3. Leveranser</h2>
    <ul>
      <li>Full OpenBSD ports-import med nattlig jobb</li>
      <li>AI-assistent for pakkeutforskning</li>
      <li>WCAG 2.2 AA-mål for tilgjengelig grensesnitt</li>
    </ul>
  BODY

add_app applications,
  file: "19_pub_healthcare_helseteknologi.html",
  title: "Søknad — pub.healthcare helseteknologi",
  funder: "Helseinnovasjon",
  to: APPLICANT[:email],
  subject: "Søknad: pub.healthcare — AI-drevet helsetransformasjon",
  contact_url: "https://www.pub.healthcare",
  deadline: "Tilpass per giver",
  track: "helse",
  project: "pub.healthcare",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>pub.healthcare utvikler AI-drevne verktøy for norsk helsevesen — koordinering, simulering og effektivisering — med MASTER som utviklingsmotor og RAILS som leveranseplattform.</p>

    <h2>2. Behov</h2>
    <p>Administrativ byrde, fragmentert samhandling og avhengighet av utenlandske systemer svekker helsetjenesten. Vi trenger norske, sikre, åpne alternativer.</p>

    <h2>3. Leveranser</h2>
    <ul>
      <li>Prototyper for pasient/pårørende-koordinering</li>
      <li>Koordinering og informasjon (ikke diagnose)</li>
      <li>Pilot med Helse Vest-partner</li>
      <li>TRL 4–5 dokumentasjon</li>
    </ul>

    <h2>4. Budsjett</h2>
    <p><strong>Prosjektramme:</strong> NOK #{FundingHelpers.fmt(FUNDING.dig("ventures", "pub_healthcare", "project_total_nok"))} (12 mnd). <strong>IN-mål:</strong> #{FundingHelpers.innovasjon_ask_text("pub_healthcare", FUNDING)} med Helse Vest-partner.</p>
  BODY

add_app applications,
  file: "20_syre_footwear_innovasjon.html",
  title: "Søknad — SYRE™ skoinnovasjon",
  funder: "Produktinnovasjon / moteindustri",
  to: APPLICANT[:email],
  subject: "Søknad: SYRE™ — bærekraftig skoinnovasjon fra Bergen",
  contact_url: "https://stipendportalen.no",
  deadline: "Tilpass per giver",
  track: "produkt",
  project: "syre",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>SYRE™ er bergensk skoinnovasjon — design, prototyping og produksjon med MASTER-drevet produktutvikling og HTU-klar dokumentasjon for Innovasjon Norge og legater.</p>

    <h2>2. Innovasjon</h2>
    <p>Lokal produksjon, bærekraftige materialer og direkte-til-forbruker-modell reduserer transport og styrker vestlandsk næringsliv.</p>

    <h2>3. Finansiering</h2>
    <p><strong>Prosjektramme:</strong> NOK #{FundingHelpers.fmt(FUNDING.dig("ventures", "syre", "project_total_nok"))} (12 mnd, prototyping først).</p>
    <p><strong>Legat:</strong> #{FundingHelpers.legat_ask_text("syre", FUNDING)} · <strong>IN-mål:</strong> #{FundingHelpers.innovasjon_ask_text("syre", FUNDING)}</p>
  BODY

add_app applications,
  file: "21_norwegian_hedge_finans.html",
  title: "Søknad — Norwegian Hedge",
  funder: "Finansinnovasjon",
  to: APPLICANT[:email],
  subject: "Søknad: Norwegian Hedge — ansvarlig finans og risikostyring",
  contact_url: "https://stipendportalen.no",
  deadline: "Tilpass per giver",
  track: "finans",
  project: "norwegian_hedge",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Norwegian Hedge utvikler finansielle verktøy for ansvarlig risikostyring — bygget med MASTER/RAILS. Målet er transparens, norsk reguleringsetterlevelse og demokratisert tilgang til hedging-kompetanse.</p>

    <h2>2. Samfunnsnytte</h2>
    <p>Små bedrifter og enkeltpersoner i Bergen mangler verktøy som tidligere kun var tilgjengelig for store aktører. MASTER muliggjør sikker, revisjonert kode til rimelig kostnad.</p>
  BODY

add_app applications,
  file: "22_ditt_parti_demokrati.html",
  title: "Søknad — Ditt Parti",
  funder: "Demokratisk innovasjon",
  to: APPLICANT[:email],
  subject: "Søknad: Ditt Parti — lokal politisk mobilisering i Bergen",
  contact_url: "https://stipendportalen.no",
  deadline: "Tilpass per giver",
  track: "samfunn",
  project: "ditt_parti",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Ditt Parti er hyperlokal digital politisk mobilisering for Bergen — bydelsrom, åpne budsjettforslag og MASTER-drevet oversettelse av politisk jargon til klart norsk.</p>

    <h2>2. Problem</h2>
    <p>Lav valgdeltakelse og fragmentert informasjon. Unge og nye innbyggere faller utenfor.</p>

    <h2>3. Mål</h2>
    <table>
      <tr><td>1.</td><td>+15 prosentpoeng lokal valgdeltakelse innen 2028</td></tr>
      <tr><td>2.</td><td>Sanntids åpen finansiering</td></tr>
      <tr><td>3.</td><td>Åpent API for forskning</td></tr>
    </table>
  BODY

add_app applications,
  file: "23_ilumi_gravferd_verdighet.html",
  title: "Søknad — Ilumi Gravferd",
  funder: "Humanitære tjenester",
  to: APPLICANT[:email],
  subject: "Søknad: Ilumi Gravferd — verdig minneseremoni i Bergen",
  contact_url: "https://stipendportalen.no",
  deadline: "Tilpass per giver",
  track: "sosial",
  project: "ilumi",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Ilumi Gravferd tilbyr rolige, transparente gravferdstjenester for familier i Bergen — med MASTER-drevet planlegging og fastpris uten skjulte tillegg.</p>

    <h2>2. Samfunnsnytte</h2>
    <p>I sårbare faser trenger familier trygghet og klarhet — ikke byråkrati. Lavterskel rådgivning for lavinntektsfamilier er eksplisitt mål.</p>

    <h2>3. Budsjett</h2>
    <p><strong>Prosjektramme:</strong> NOK #{FundingHelpers.fmt(FUNDING.dig("ventures", "ilumi_gravferd", "project_total_nok"))} (12 mnd). <strong>Legat:</strong> #{FundingHelpers.legat_ask_text("ilumi_gravferd", FUNDING)}</p>
    <p><em>Verdighet først — ingen gimmick-produkter uten opt-in.</em></p>
  BODY

add_app applications,
  file: "24_digitaliseringsdirektoratet.html",
  title: "Søknad — Digital offentlig sektor",
  funder: "Digitaliseringsdirektoratet",
  to: "post@digdir.no",
  subject: "Søknad: MASTER/RAILS — suveren AI for offentlig sektor",
  contact_url: "https://www.digdir.no",
  deadline: "Se digdir.no utlysninger",
  track: "offentlig",
  project: "pub4",
  body: standard_sections(
    project: "sovereign_vps",
    funder_type: :innovasjon,
    funder_id: "digdir",
    angle: "Digdir fremmer digitalisering med trygghet og personvern. MASTER + RAILS leverer åpen, sporbar, selvkorrigerende utvikling — alternativ til utenlandsk SaaS.",
    deliverables: [
      "Referansearkitektur for ansvarlig AI i offentlige anskaffelser",
      "Pilot med norsk kommune eller etat",
      "Sikkerhetsvurdering etter NSM-prinsipper",
      "Dokumentasjon på klart norsk",
    ]
  )

add_app applications,
  file: "25_gjensidigestiftelsen_helse.html",
  title: "Søknad — Folkehelse og forebygging",
  funder: "Gjensidigestiftelsen",
  to: "stiftelsen@gjensidige.no",
  subject: "Søknad: pub.healthcare — forebyggende helseteknologi",
  contact_url: "https://www.gjensidigestiftelsen.no",
  deadline: "Se gjensidigestiftelsen.no",
  track: "helse",
  project: "pub.healthcare",
  body: standard_sections(
    project: "pub_healthcare",
    funder_type: :legat,
    funder_id: "gjensidigestiftelsen",
    angle: "Gjensidigestiftelsen støtter folkehelse og forebygging. Digitale verktøy som øker selvstendighet og trygghet passer direkte.",
    deliverables: [
      "Prototyp for forebyggende helseoppfølging",
      "Pasient/pårørende-informasjonsportal",
      "Evaluering med brukerrepresentanter",
      "Åpen metodikk for replikering",
    ]
  )

add_app applications,
  file: "26_kavlitrust_samfunnsnytte.html",
  title: "Søknad — Samfunnsnyttig innovasjon",
  funder: "Kavli Trust",
  to: "post@kavlitrust.com",
  subject: "Søknad: MASTER/RAILS — samfunnsnyttig teknologi fra Bergen",
  contact_url: "https://kavlitrust.com",
  deadline: "Se kavlitrust.com",
  track: "samfunn",
  project: "pub4",
  body: standard_sections(
    project: "brgen",
    angle: "Kavli Trust støtter forskning og samfunnsnytte. pub4 kombinerer teknologisk innovasjon med konkret nytte for innbyggere.",
    deliverables: [
      "Dokumentert samfunnsnytte i Bergen",
      "Åpen forsknings- og utviklingsrapport",
      "Brukerinvolvering i design",
      "Bærekraftig driftsmodell",
    ]
  )

add_app applications,
  file: "27_legeforeningen_forskning.html",
  title: "Søknad — Medisinsk programvareforskning",
  funder: "Den norske legeforening",
  to: "post@legeforeningen.no",
  subject: "Søknad: MASTER-drevet utvikling av medisinsk programvare",
  contact_url: "https://www.legeforeningen.no",
  deadline: "Se legeforeningen.no stipender",
  track: "helse",
  project: "pub.healthcare",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Jeg søker støtte til utvikling av medisinsk programvare med MASTER/RAILS — med fokus på klinisk nyttige verktøy, sporbarhet og pasientsikkerhet.</p>

    <h2>2. Klinisk relevans</h2>
    <p>Legeforeningen forstår gapet mellom IT-leverandører og klinisk praksis. MASTER muliggjør rask iterasjon med høy kodekvalitet — nærmere klinikerens behov.</p>

    <h2>3. Etikk og sikkerhet</h2>
    <p>Konstitusjonelle prinsipper, OpenBSD-inspirert sikkerhet og menneskelig kontroll i alle beslutningsløkker.</p>
  BODY

add_app applications,
  file: "28_media_city_bergen.html",
  title: "Søknad — Medieteknologi og kultur",
  funder: "Media City Bergen / regionale kulturfond",
  to: APPLICANT[:email],
  subject: "Søknad: brgen.no TV og medieteknologi — Media City Bergen",
  contact_url: "https://www.mediacitybergen.no",
  deadline: "Se aktuelle utlysninger",
  track: "kultur",
  project: "brgen",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>To komplementære spor: <strong>brgen.no</strong> (bydelsmedia, livestream, fellesskaps-TV) og <strong>Repligen Studio</strong> (visuell produksjon for lokale aktører). Begge er RAILS-apper utviklet med MASTER — relevant for Media City Bergen.</p>

    <h2>2. brgen.no — medieteknologi</h2>
    <ul>
      <li>Bydelskanaler og livestream med norsk infrastruktur</li>
      <li>MASTER-drevet moderering og tilgjengelighet</li>
      <li>Creator-økonomi uten utenlandsk plattformavhengighet</li>
    </ul>

    <h2>3. Repligen Studio — visuell produksjon</h2>
    <ul>
      <li>Respektfulle bilder og video for kulturaktører</li>
      <li>Samtykke-mal og etterrettelig produksjonslogg</li>
      <li>Pilot med én Bergen-aktør (kultur/kommune)</li>
    </ul>
  BODY

add_app applications,
  file: "29_openbsd_foundation_sikkerhet.html",
  title: "Søknad — OpenBSD og sikker infrastruktur",
  funder: "Open Source / sikkerhetsmiljø",
  to: APPLICANT[:email],
  subject: "Søknad: pub4 — OpenBSD-integrert AI-utvikling",
  contact_url: "https://www.openbsdfoundation.org",
  deadline: "Varierer",
  track: "sikkerhet",
  project: "master+bsdports",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>pub4 integrerer OpenBSD pledge(2) og capsicum(4) i MASTERs kjøremiljø og bsdports.org som RAILS-app. Dette er digital suverenitet i praksis.</p>

    <h2>2. Behov</h2>
    <p>AI-systemer kjører ofte med for brede rettigheter. Vi demonstrerer minimal-privilege AI-utvikling med produksjonsklare apper.</p>

    <h2>3. Leveranser</h2>
    <ul>
      <li>Dokumentert OpenBSD-deploy for MASTER + RAILS</li>
      <li>bsdports full import og sårbarhetsovervåking</li>
      <li>Referanse for andre sikkerhetsmiljøer</li>
    </ul>
  BODY

add_app applications,
  file: "30_boligsparing_egenkapital.html",
  title: "Søknad — Egenkapital til boligkjøp",
  funder: "Generelle legater / økonomisk støtte",
  to: APPLICANT[:email],
  subject: "Søknad: Egenkapitalstøtte til boligkjøp i Bergen",
  contact_url: "https://stipendportalen.no/organisasjoner?location=37",
  deadline: "Varierer — sjekk stipendportalen.no",
  track: "bolig",
  project: "personal",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Jeg søker legatstøtte til egenkapital for kjøp av leilighet i Bergen. Ærlig formål: varig boligstabilitet. Jeg er ikke-konfidensiell om at dette er separat fra, men komplementært til, MASTER/RAILS-prosjektfinansiering.</p>

    <h2>2. Bakgrunn</h2>
    <p>Som gründer med pågående innovasjonsarbeid mangler jeg tilstrekkelig egenkapital til bankfinansiering. Legater som støtter utdanning, næringsdrift eller vanskeligstilte bergensere er relevante.</p>

    <h2>3. Plan</h2>
    <table>
      <tr><td>1.</td><td>Mål: leilighet 2–3 rom i Bergen, under markedsmedian</td></tr>
      <tr><td>2.</td><td>Parallelt: Startlån-søknad til kommunen</td></tr>
      <tr><td>3.</td><td>Inntektsplan: PubHealthcare-prosjekter og RAILS-apper</td></tr>
    </table>
  BODY

# --- More Bergen legats (stipendportalen / legathåndboken) ---

add_app applications,
  file: "31_zuccarellostiftelsen.html",
  title: "Søknad — Personstipend høsten 2026",
  funder: "Zuccarellostiftelsen",
  to: "post@zuccarellostiftelsen.no",
  subject: "Søknad Zuccarellostiftelsen personstipend 2026",
  contact_url: "https://stipendportalen.no/utlysing/4985",
  deadline: "01.09.2026",
  track: "bolig",
  project: "personal",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Jeg søker personstipend fra Zuccarellostiftelsen. Som bosatt i Bergen med økonomisk press søker jeg ærlig støtte til grunnleggende behov og deltakelse — ikke pakket inn som noe annet.</p>
    #{FundingHelpers.personal_use_of_funds_block(FUNDING)}
  BODY

add_app applications,
  file: "32_hielmstierne_rosencrone.html",
  title: "Søknad — Sosial bistand",
  funder: "Den Grevelige Hielmstierne-Rosencroneske Stiftelse",
  to: "postmottak@bergen.kommune.no",
  subject: "Søknad Hielmstierne-Rosencrone — bistand bosatt i Bergen",
  contact_url: "https://stipendportalen.no/organisasjon/1218",
  deadline: "Årlig — se vedtekter",
  track: "sosial",
  project: "personal",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Jeg søker bistand fra stiftelsen som bosatt i Bergen. Stiftelsen utdeler til trengende personer i Bergen — jeg søker ærlig om økonomisk støtte i en vanskelig periode.</p>
    <h2>2. Situasjon</h2>
    <p>Enkeltperson med innovasjonsarbeid uten stabil lønn, høye boligkostnader i Bergen, og behov for brofinansiering til varig boligløsning.</p>
  BODY

add_app applications,
  file: "33_willy_brandt_norsk_tysk.html",
  title: "Søknad — Norsk-tysk innovasjon",
  funder: "Den norsk-tyske Willy Brandt-stiftelsen",
  to: "post@willy-brandt-stiftelsen.no",
  subject: "Søknad: MASTER/RAILS — norsk-tysk teknologisamarbeid",
  contact_url: "https://stipendportalen.no/utlysing/3859",
  deadline: "Fortløpende",
  track: "nordic",
  project: "pub4",
  body: standard_sections(
    project: "bsdports",
    angle: "Willy Brandt-stiftelsen fremmer norsk-tyske forbindelser. MASTER/RAILS kan samarbeide med tyske miljøer om åpen, sikker programvare og helseteknologi.",
    deliverables: [
      "Felles workshop Bergen–Tyskland",
      "Dokumentasjon på tysk og norsk",
      "Åpen kildekode-demo av bsdports/brgen",
      "Rapport til stiftelsen",
    ]
  )

add_app applications,
  file: "34_uib_forskning_legat.html",
  title: "Søknad — Forskning og utdanning",
  funder: "Universitetet i Bergen — fond og legater",
  to: "post@uib.no",
  subject: "Søknad UiB legat — selvforbedrende AI og helseteknologi",
  contact_url: "https://www4.uib.no/for-studenter/livet-som-student/fond-legater-og-stipend",
  deadline: "Varierer per fond",
  track: "forskning",
  project: "master",
  body: standard_sections(
    project: "master",
    funder_type: :legat,
    angle: "UiB-fond støtter studenter og forskere i Bergen. MASTER-arbeidet har forskningsverdi innen IKT og medisinsk informatikk.",
    deliverables: [
      "Forskningsnotat eller artikkelutkast",
      "Presentasjon for UiB-miljø",
      "Kontakt med Det medisinske fakultet for Mohn-spor",
      "Åpen metodikk-dokumentasjon",
    ]
  )

add_app applications,
  file: "35_ekom_programmet.html",
  title: "Søknad — Digital innovasjon",
  funder: "Norges forskningsråd / Ekom-programmet",
  to: "post@forskningsradet.no",
  subject: "Søknad: MASTER — pålitelig AI-infrastruktur for digital Norge",
  contact_url: "https://www.forskningsradet.no",
  deadline: "Se IKT-utlysninger",
  track: "innovasjon",
  project: "master",
  body: standard_sections(
    project: "master",
    funder_type: :forskning,
    funder_id: "forskningsradet",
    angle: "Ekom og IKT-programmer søker digital suverenitet og innovasjon. MASTER + OpenBSD + RAILS er et komplett svar.",
    deliverables: [
      "Referansearkitektur for ansvarlig AI",
      "Produksjonsklare RAILS-apper",
      "Sikkerhetsrevisjon",
      "Overførbar metodikk",
    ]
  )

add_app applications,
  file: "36_dam_stiftelsen_helse.html",
  title: "Søknad — Helseforskning og innovasjon",
  funder: "Dam Foundation",
  to: "post@dam.no",
  subject: "Søknad Dam: pub.healthcare — folkehelse og digitalisering",
  contact_url: "https://dam.no",
  deadline: "Se dam.no utlysninger",
  track: "helse",
  project: "pub.healthcare",
  body: standard_sections(
    project: "pub_healthcare",
    angle: "Dam støtter helseforskning og folkehelse. pub.healthcare adresserer koordinering, trygghet og selvstendighet.",
    deliverables: [
      "Pilot med pasientorganisasjon",
      "Evaluering av brukeropplevelse",
      "Åpen dokumentasjon",
      "Grunnlag for Helse Vest-samarbeid",
    ]
  )

add_app applications,
  file: "37_exxonmobil_fondet.html",
  title: "Søknad — Teknologi og utdanning",
  funder: "ExxonMobils fond i Norge",
  to: "post@exxonmobil.no",
  subject: "Søknad ExxonMobil fond — teknologisk kompetanse i Bergen",
  contact_url: "https://stipendportalen.no/stotteordninger",
  deadline: "Se stipendportalen.no",
  track: "utdanning",
  project: "master",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Jeg søker støtte til teknologisk kompetanseutvikling i Bergen — MASTER/RAILS-arbeid med sikker programvare, AI og praktiske webapplikasjoner.</p>
    <h2>2. Formål</h2>
    <p>Fond som støtter utdanning og teknologi i Norge. Mitt arbeid produserer reelle applikasjoner og dokumentert læring.</p>
  BODY

add_app applications,
  file: "38_mowinckel_forskning.html",
  title: "Søknad — Medisinsk forskning",
  funder: "Mowinckel-Stiftelsen",
  to: "post@mowinckel-stiftelsen.no",
  subject: "Søknad Mowinckel: medisinsk programvare og AI",
  contact_url: "https://stipendportalen.no/stotteordninger",
  deadline: "Se utlysninger",
  track: "helse",
  project: "pub.healthcare",
  body: <<~BODY
    <h2>1. Sammendrag</h2>
    <p>Mowinckel-Stiftelsen støtter medisinsk forskning. pub.healthcare + MASTER tilbyr programvare for simulering, koordinering og informasjon (ikke diagnose) — med norsk datasuverenitet.</p>
    <p>#{FundingHelpers::MASTER_BLURB}</p>
    <h2>2. Leveranser</h2>
    <ul>
      <li>Medisinsk programvareprototyp</li>
      <li>Samarbeid med Helse Bergen/UiB</li>
      <li>Publiserbar metodikk</li>
    </ul>
  BODY

add_app applications,
  file: "39_anders_jahres_pris.html",
  title: "Søknad — Medisinsk forskning og utvikling",
  funder: "Anders Jahres stiftelse til vitenskapens fremme",
  to: "post@anders-jahres-stiftelse.no",
  subject: "Søknad Anders Jahre: MASTER-drevet medisinsk programvare",
  contact_url: "https://www.anders-jahres-stiftelse.no",
  deadline: "Se årlige utlysninger",
  track: "helse",
  project: "pub.healthcare",
  body: standard_sections(
    project: "pub_healthcare",
    funder_type: :legat,
    angle: "Anders Jahre-stiftelsen belønner medisinsk forskning og utvikling. MASTER muliggjør rask, sikker iterasjon av medisinsk programvare.",
    deliverables: [
      "Forskningsrapport",
      "Prototyp for klinisk/administrativ nytte",
      "Etisk og sikkerhetsgjennomgang",
      "Presentasjon for stiftelsen",
    ]
  ) + FundingHelpers.anders_jahre_disclaimer_block

add_app applications,
  file: "40_master_rails_konsolidert.html",
  title: "Utvikling av suveren AI-plattform og helsetjenesteapplikasjoner",
  funder: "Generell søknad — alle givere",
  to: APPLICANT[:email],
  subject: "Søknad: MASTER + RAILS — konsolidert prosjektbeskrivelse",
  contact_url: "https://stipendportalen.no",
  deadline: "Tilpass per giver",
  track: "innovasjon",
  project: "master+rails",
  body: <<~BODY
    <h2>1. Prosjekttittel</h2>
    <p><strong>Utvikling av en suveren, selvforbedrende AI-plattform og sikre helsetjenesteapplikasjoner (MASTER + RAILS)</strong></p>

    <h2>2. Sammendrag</h2>
    <p>Prosjektet videreutvikler et konstitusjonelt styrt, selvforbedrende AI-system (MASTER) sammen med praktiske Ruby on Rails-applikasjoner. Målet er norsk kontrollert, høy-sikkerhets AI-infrastruktur som styrker trygghet, selvstendighet og effektivitet i offentlig helsetjeneste.</p>
    <p>Plattformen kombinerer OpenBSD-inspirert sikkerhet, etisk AI-styring og rask applikasjonsutvikling — med full datasuverenitet og sporbarhet.</p>

    <h2>3. Bakgrunn og behov</h2>
    <p>Norsk offentlig sektor digitaliserer under press fra personvern, sikkerhet og etikk. Mange AI-løsninger er utenlandskkontrollerte. Samtidig trenger helsepersonell verktøy som reduserer administrativ byrde og styrker samhandling mellom pasienter, pårørende og tjenesteytere.</p>

    <h2>4. Prosjektmål</h2>
    <ul>
      <li>Videreutvikle MASTER med konstitusjonelle prinsipper og sikkerhetsgarantier</li>
      <li>Pilotere sikre Rails-apper for helsekoordinering og offentlige tjenester</li>
      <li>Etablere norsk suveren AI-infrastruktur for flere sektorer</li>
      <li>Måle forbedring i utviklingshastighet, kodekvalitet og pålitelighet</li>
      <li>Forberede samarbeid med forskning og offentlige aktører</li>
    </ul>

    <h2>5. Teknisk tilnærming</h2>
    <p><strong>MASTER (direkte):</strong> Selvforbedrende multi-agent AI med kontinuerlig selvrefinering og konstitusjonell styring i minimal-tillit-miljø.</p>
    <p><strong>RAILS (indirekte):</strong> Rails 8-applikasjoner — brgen.no, amber.brgen.no, bsdports.org — som konkrete leveranser MASTER utvikler og forbedrer.</p>

    <h2>6. Forventet virkning</h2>
    <ul>
      <li>Effektivisering og kvalitet i helsetjenesten</li>
      <li>Digital suverenitet — redusert avhengighet av utenlandsk AI</li>
      <li>Etisk og sikker AI-utvikling fra grunnen av</li>
      <li>Styrket norsk innovasjonskapasitet</li>
    </ul>

    <h2>7. Gjennomføring</h2>
    <p><strong>Fase 1 (mnd 1–6):</strong> Kjernesystem, sikkerhet, helseprototyper.</p>
    <p><strong>Fase 2 (mnd 7–12):</strong> Pilotering, tilbakemeldinger, dokumentasjon.</p>

    <h2>8. Organisering</h2>
    <p>Prosjektet ledes av #{APPLICANT[:name]} gjennom #{APPLICANT[:org]} (#{APPLICANT[:address]}). Flere års utvikling innen AI, sikkerhet og Rails. Samarbeid med forskning og helse planlegges.</p>

    <h2>9. Budsjett</h2>
    <p><strong>Prosjektramme:</strong> NOK #{FundingHelpers.fmt(FUNDING.dig("ventures", "master", "project_total_nok"))} (12 mnd, solo enkeltpersonforetak).</p>
    <p><strong>IN-mål:</strong> #{FundingHelpers.innovasjon_ask_text("master", FUNDING)} · <strong>Legat:</strong> #{FundingHelpers.legat_ask_text("master", FUNDING)}</p>
    <p class="meta">Se master.html for full breakdown. SkatteFUNN = skattefradrag, ikke kontant.</p>
  BODY

# --- Wholesome meta → ekte kanal (draft) ---

fun_item = FUNDING.fetch("fun_wholesome", []).find { |x| x["id"] == "legat_soker_fo" }
if fun_item
  add_app applications,
    file: "66_legat_soker_fo_draft.html",
    title: "Søknad — FoU på ansvarlig legat-automatisering (utkast)",
    funder: "SkatteFUNN / Forskningsrådet",
    to: "skattefunn@forskningsradet.no",
    subject: "Utkast: grok_send_legats.rb — menneskelig godkjenning før sending",
    contact_url: "https://www.skattefunn.no",
    deadline: "Løpende — utkast, ikke send uten manuell gjennomgang",
    track: "innovasjon",
    project: "master",
    draft: true,
    body: <<~BODY
      <h2>1. Sammendrag</h2>
      <p>#{fun_item['wholesome_angle']}</p>
      <p>Dette er et <strong>utkast</strong> — ikke send automatisk. All mutt/grok-sending krever manuell verifisering av mottaker og innhold.</p>
      <p>#{FundingHelpers::MASTER_BLURB}</p>

      <h2>2. FoU-problem</h2>
      <p>Hvordan automatisere søknadsproduksjon og sending uten å miste ærlighet, finansiell nøyaktighet og menneskelig kontroll?</p>

      <h2>3. Leveranser</h2>
      <ul>
        <li>grok_send_legats.rb med dry-run og sent_log.yml</li>
        <li>funding.yml som eneste sannhetskilde for beløp</li>
        <li>Dokumentert menneske-i-løkke før e-post</li>
      </ul>

      #{FundingHelpers.legat_budget_section("master", FUNDING, funder_type: :skattefunn)}
    BODY
end

# --- Bergen catalog (legathåndboken / stipendportalen) ---

def body_from_template(entry)
  venture = FundingHelpers.resolve_venture(entry.fetch("project", "personal"))
  amount_note = entry["amount"].to_s.strip
  amount_html = amount_note.empty? ? "" : "<p class=\"meta\"><strong>Søkt beløp (katalog):</strong> #{amount_note}</p>\n"
  case entry["template"]
  when "sosial"
    <<~BODY
      <h2>1. Sammendrag</h2>
      <p>Jeg søker støtte fra <strong>#{entry["funder"]}</strong>. #{entry["angle"]}</p>
      <p>#{FUNDING.dig("ventures", "personal", "wholesome_pitch")}</p>
      <h2>2. Situasjon</h2>
      <p>Enkeltperson med pågående innovasjonsarbeid (MASTER/RAILS/pub.healthcare) uten stabil lønnsinntekt. Parallelt arbeider jeg med legitim teknologiutvikling som kan skape varig inntekt.</p>
      #{FundingHelpers.personal_use_of_funds_block(FUNDING)}
      #{FundingHelpers.claims_block("personal", FUNDING)}
    BODY
  when "utdanning"
    <<~BODY
      <h2>1. Sammendrag</h2>
      <p>#{entry["angle"]} Jeg er bosatt i Bergen og utvikler kompetanse innen AI, sikker programvare og Rails gjennom MASTER/RAILS-prosjektet.</p>
      <h2>2. Studie-/kompetanseplan</h2>
      <p>MASTER er et selvrefinerende AI-system; RAILS-mappen inneholder deploybare applikasjoner. Arbeidet er praktisk, dokumentert utdanning på høyt nivå.</p>
      <h2>3. Bruk av midler</h2>
      <table>
        <tr><td>1.</td><td>Kurs, konferanser og faglitteratur</td></tr>
        <tr><td>2.</td><td>Nødvendig utstyr for studie og utvikling</td></tr>
        <tr><td>3.</td><td>Reise til UiB, Helse Bergen og fagmiljø</td></tr>
      </table>
    BODY
  when "helse"
    v = FUNDING["ventures"]["pub_healthcare"]
    <<~BODY
      <h2>1. Sammendrag</h2>
      <p>Jeg søker støtte til helserelatert innovasjon via pub.healthcare og MASTER/RAILS. #{entry["angle"]}</p>
      <p>#{v["wholesome_pitch"]}</p>
      <p>#{FundingHelpers::MASTER_BLURB}</p>
      <h2>2. Pasient- og samfunnsnytte</h2>
      <p>Velferdsteknologi skal styrke trygghet, selvstendighet og ressursutnyttelse — i tråd med norsk velferdsmodell. Ikke diagnose eller behandlingsbeslutninger.</p>
      <h2>3. Leveranser</h2>
      <ul>
        #{v["deliverables"].map { |d| "<li>#{d}</li>" }.join("\n        ")}
      </ul>
      #{FundingHelpers.legat_budget_section("pub_healthcare", FUNDING)}
    BODY
  when "kultur"
    <<~BODY
      <h2>1. Sammendrag</h2>
      <p>#{entry["angle"]}</p>
      <p>#{FundingHelpers::RAILS_BLURB}</p>
      <h2>2. Kunstnerisk og teknisk innovasjon</h2>
      <p>MASTER muliggjør rask, sikker utvikling av digitale opplevelser — med respekt for estetikk, tilgjengelighet og lokalt innhold.</p>
      <h2>3. Leveranser</h2>
      <ul>
        <li>Pilot med publikum eller brukere i Bergen</li>
        <li>Åpen dokumentasjon</li>
        <li>Presentasjon for giver</li>
      </ul>
    BODY
  when "bolig"
    <<~BODY
      <h2>1. Sammendrag</h2>
      <p>#{entry["angle"]}</p>
      #{amount_html}
      <p>#{FUNDING.dig("ventures", "bolig_bergen", "wholesome_pitch")}</p>
      #{FundingHelpers.bolig_channels_block(FUNDING)}
      #{FundingHelpers.boligpakke_block(FUNDING)}
      #{FundingHelpers.claims_block("bolig_bergen", FUNDING)}
    BODY
  when "nav_service"
    <<~BODY
      <h2>1. Henvendelse</h2>
      <p>#{entry["angle"]}</p>
      #{FundingHelpers.nav_service_block}
      #{FundingHelpers.boligpakke_block(FUNDING)}
    BODY
  when "maritim"
    FundingHelpers.maritim_template_body(entry, FUNDING)
  when "autisme"
    FundingHelpers.helse_template_body(entry, FUNDING, variant: :autisme)
  when "mental_helse"
    FundingHelpers.helse_template_body(entry, FUNDING, variant: :mental_helse)
  when "revmatiker"
    FundingHelpers.helse_template_body(entry, FUNDING, variant: :revmatiker)
  else
    funder_id = entry["funder_id"]
    funder_type = entry["funder_type"]&.to_sym || :legat
    standard_sections(
      project: entry.fetch("project", "master"),
      funder_type: funder_type,
      funder_id: funder_id,
      angle: entry.fetch("angle", "Prosjektet kombinerer MASTER direkte og RAILS indirekte."),
      deliverables: entry.fetch("deliverables", FundingHelpers.venture_data(FUNDING, venture)&.dig("deliverables") || [
        "Modnet MASTER-kjerne",
        "Pilotklare RAILS-applikasjoner",
        "Dokumentasjon og rapport til giver",
      ]),
    )
  end
end

catalog_path = File.join(LEGATS_DIR, "bergen_catalog.yml")
if File.exist?(catalog_path)
  catalog = YAML.load_file(catalog_path)
  catalog.fetch("legater", []).each do |entry|
    add_app applications,
      file: "#{entry['id']}.html",
      title: entry["title"],
      funder: entry["funder"],
      to: entry["to"],
      subject: entry["subject"],
      contact_url: entry["contact_url"],
      deadline: entry["deadline"],
      track: entry["track"],
      project: entry["project"],
      funder_id: entry["funder_id"],
      draft: entry["draft"] == true,
      cover_intro: entry["cover_intro"],
      amount: entry["amount"],
      body: body_from_template(entry)
  end
end

# --- Venture × funder matrix (maks dekning) ---

FUNDER_EMAIL = {
  "innovasjon_norge" => "post@innovasjonnorge.no",
  "skattefunn" => "skattefunn@forskningsradet.no",
  "helse_vest" => "post@helse-vest.no",
  "sr_bank" => "post@srstiftelsen.no",
  "bergen_utdanning" => "postmottak@bergen.kommune.no",
  "gunvor_minde" => "postmottak@bergen.kommune.no",
  "vanskeligstilte" => "postmottak@bergen.kommune.no",
  "startlan" => "boligkontoret@bergen.kommune.no",
  "anthon" => "post@anthonstiftelsen.no",
  "wahlstrom" => "postmottak@bergen.kommune.no",
  "trond_mohn" => "post@mohnfoundation.no",
  "forskningsradet" => "post@forskningsradet.no",
  "vestland_fylke" => "post@vestlandfylke.no",
  "gjensidigestiftelsen" => "stiftelsen@gjensidige.no",
  "det_bergenske" => "post@detbergenskestiftelse.no",
  "media_city" => "post@mediacitybergen.no",
  "digdir" => "post@digdir.no",
}.freeze

FUNDER_TYPE_MAP = {
  "tilskudd_lan" => :innovasjon,
  "skattefradrag" => :skattefunn,
  "forskningsprosjekt" => :forskning,
  "forskningsstotte" => :forskning,
  "innovasjonsmidler" => :innovasjon,
  "utlysning" => :innovasjon,
  "lan_tilskudd" => :legat,
}.freeze

def funder_covered?(apps, venture, funder_id, funder_name)
  needle = funder_name.to_s.downcase[0, 24]
  apps.any? do |a|
    FundingHelpers.resolve_venture(a[:project]) == venture &&
      (a[:file].to_s.include?(funder_id.to_s) || a[:funder].to_s.downcase.include?(needle))
  end
end

FUNDING["ventures"].each do |venture, vdata|
  next if %w[personal bolig_bergen].include?(venture)

  FUNDING["funders"].each do |f|
    next if f["type"] == "meta"
    next unless f["fit"]&.include?(venture)
    next if funder_covered?(applications, venture, f["id"], f["name"])

    ftype = FUNDER_TYPE_MAP[f["type"]] || :legat
    email = FUNDER_EMAIL[f["id"]] || APPLICANT[:email]
    track = vdata["track"] || "innovasjon"

    add_app applications,
      file: "vx_#{venture}_#{f['id']}.html",
      title: "Søknad — #{vdata['title']}",
      funder: f["name"],
      to: email,
      subject: "Søknad: #{vdata['title']} — #{f['name']}",
      contact_url: "https://stipendportalen.no/organisasjoner?location=37",
      deadline: "Tilpass per giver — verifiser på contact_url",
      track: track,
      project: venture,
      low_priority: true,
      body: standard_sections(
        project: venture,
        funder_type: ftype,
        funder_id: f["id"],
        angle: "#{f['name']} — #{vdata['wholesome_pitch']}",
        deliverables: vdata["deliverables"] || ["Dokumentasjon og rapport til giver"],
      )
  end
end

FUNDING.fetch("fun_wholesome", []).each do |item|
  next unless item["realistic"]
  venture = item["funder_match"]
  next unless venture && FUNDING["ventures"][venture]

  add_app applications,
    file: "fun_#{item['id']}.html",
    title: "Søknad — #{item['name']}",
    funder: "Se funding.yml / matchende giver",
    to: APPLICANT[:email],
    subject: "Søknad: #{item['name']}",
    contact_url: "https://stipendportalen.no",
    deadline: "Tilpass per giver",
    track: FUNDING.dig("ventures", venture, "track") || "innovasjon",
    project: venture,
    draft: true,
    body: <<~BODY
      <h2>1. Sammendrag</h2>
      <p>#{item['wholesome_angle']}</p>
      <p class="meta">Vinkel fra fun_wholesome — koble til #{venture}.html og riktig giver før sending.</p>
      #{FundingHelpers.legat_budget_section(venture, FUNDING)}
    BODY
end

# --- Generate HTML files ---

manifest_entries = []

applications.each do |app|
  funder_record = funder_record_for(app)
  meta = applicant_meta(funder: app[:funder])
  wrap_letter(
    title: app[:title],
    meta: meta,
    body: app[:body],
    outfile: app[:file],
    funder_id: app[:funder_id] || funder_record&.dig("id"),
  )

  entry = {
    "id" => app[:file].sub(/\.html$/, ""),
    "file" => "legats/#{app[:file]}",
    "funder" => app[:funder],
    "to" => app[:to],
    "subject" => app[:subject],
    "contact_url" => app[:contact_url],
    "deadline" => app[:deadline],
    "track" => app[:track],
    "project" => app[:project],
    "from" => APPLICANT[:email],
    "verify_to" => true,
    "draft" => app[:draft] == true,
    "sendable" => manifest_sendable?(app, funder_record),
    "notes" => manifest_notes(app, funder_record),
  }
  entry["preferred_channel"] = funder_record["preferred_channel"] if funder_record&.dig("preferred_channel")
  entry["low_priority"] = true if app[:file].to_s.start_with?("vx_") || app[:low_priority]
  entry["cover_intro"] = app[:cover_intro] if app[:cover_intro]
  entry["amount"] = app[:amount] if app[:amount]
  manifest_entries << entry
end

manifest = {
  "generated" => DATE_ISO,
  "applicant" => APPLICANT.transform_keys(&:to_s),
  "deadlines" => FUNDING.fetch("deadlines", []),
  "instructions" => [
    "1. Kjør: ruby BPLAN/build_legats.rb for å regenerere alle brev",
    "2. Verifiser to-adresser på giverens nettside — mange bruker skjema, ikke e-post",
    "3. Konverter HTML til PDF: wkhtmltopdf eller nettleser Skriv ut → Lagre som PDF",
    "4. Batch: ruby BPLAN/grok_send_legats.rb --batch bolig_asap --dry-run",
    "5. Enkelt: ./BPLAN/legat_mailer.sh dry-run ID",
    "6. Se BPLAN/legats/batches.yml for senderekkefølge",
    "7. Sendt-logg: BPLAN/legats/sent_log.yml (unngår duplikater)",
  ],
  "applications" => manifest_entries,
}

File.write(File.join(LEGATS_DIR, "manifest.yml"), manifest.to_yaml)
puts "wrote legats/manifest.yml (#{manifest_entries.size} applications)"

File.write(
  File.join(LEGATS_DIR, "index.html"),
  Bplan::Html.legats_index_html(
    manifest_entries: manifest_entries,
    funding: FUNDING,
    helpers: FundingHelpers,
  ),
)
puts "wrote legats/index.html"

Bplan::Validate.validate_all!(
  ROOT,
  funding: FUNDING,
  manifest_entries: manifest_entries,
  helpers: FundingHelpers,
)
Bplan::Validate.write_build_id!(ROOT)