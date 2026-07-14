#!/usr/bin/env ruby
# frozen_string_literal: true

# Rebuild PDF/ business plans from git history into exact HTU layout-1 shell.
require "open3"
require "nokogiri"

ROOT = File.expand_path(__dir__)
COMMIT = "37ffc068d"
HTU_CSS = "htu/htu.css"
LOGO = "htu/bergen.svg"

def git_show(path)
  out, status = Open3.capture2("git", "-C", File.expand_path("..", __dir__), "show", "#{COMMIT}:#{path}")
  status.success? ? out : nil
end

def extract_body_html(source_path)
  raw = git_show(source_path)
  return nil unless raw

  doc = Nokogiri::HTML(raw)
  main = doc.at("main") || doc.at("body")
  return "" unless main

  # Drop scripts, charts, carousels — keep prose structure only.
  main.css("script, canvas, .swiper, .chart-container, style").remove

  fragments = []
  main.element_children.each do |node|
    case node.name
    when "section", "div"
      node.css("h2, h3, p, ul, ol, dl, table").each do |child|
        fragments << child.to_html
      end
    when "h2", "h3", "p", "ul", "ol", "dl", "table"
      fragments << node.to_html
    end
  end

  fragments.join("\n      ")
end

def wrap_plan(title:, meta:, body:, outfile:, footer_name: "Ragnhild Laupsa Mæhle &amp; GK Tepstad")
  html = <<~HTML
    <!DOCTYPE html>
    <html lang="no">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{title}</title>
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400;0,500;0,600;1,400;1,500&display=swap" rel="stylesheet">
      <link rel="stylesheet" href="#{HTU_CSS}">
    </head>
    <body>
      <article>
        <img src="#{LOGO}" alt="" class="logo">
        <header>
          <h1>#{title}</h1>
          <p class="meta">#{meta}</p>
        </header>
        <div class="content">
          #{body}
        </div>
        <footer>
          <p>Med vennlig hilsen<br><strong>#{footer_name}</strong></p>
        </footer>
      </article>
    </body>
    </html>
  HTML

  File.write(File.join(ROOT, outfile), html)
  puts "wrote #{outfile}"
end

# --- syre_shoes ---
syre_body = extract_body_html("DEPLOY/bp/syre.html")
syre_images = <<~HTML
  <div class="image-grid">
    <figure><img src="assets/ivaar_fkyeah1.png" alt="SYRE skomodell 1" loading="lazy"></figure>
    <figure><img src="assets/ivaar_fkyeah2.png" alt="SYRE skomodell 2" loading="lazy"></figure>
    <figure><img src="assets/ivaar_fkyeah3.png" alt="SYRE skomodell 3" loading="lazy"></figure>
  </div>
HTML
wrap_plan(
  title: "SYRE™ — Forretningsplan",
  meta: "SYRE Footwear AS · Bergen, Norge<br>Innovasjon Norge · Legathåndboken Bergen<br><time datetime=\"2026-07-14\">14. juli 2026</time>",
  body: "#{syre_body}\n      #{syre_images}",
  outfile: "syre_shoes.html"
)

# --- norwegianhedge ---
wrap_plan(
  title: "Norwegian Hedge — Forretningsplan",
  meta: "Norwegian Hedge AS · Bergen, Norge<br>Innovasjon Norge · Nordic Prosperity Fund<br><time datetime=\"2026-07-14\">14. juli 2026</time>",
  body: extract_body_html("DEPLOY/bp/norwegianhedge.html"),
  outfile: "norwegianhedge.html"
)

# --- pub_healthcare ---
wrap_plan(
  title: "pub.healthcare — Forretningsplan",
  meta: "pub.healthcare AS · Kanalveien 10, 5068 Bergen<br>Innovasjon Norge · TRL 5→8 pilot Nord-Norge<br><time datetime=\"2026-07-14\">14. juli 2026</time>",
  body: extract_body_html("DEPLOY/bp/04_pub_healthcare.html"),
  outfile: "pub_healthcare.html"
)

# --- ditt_parti (new — never in pub4 git) ---
wrap_plan(
  title: "Ditt Parti — Forretningsplan",
  meta: "Ditt Parti AS · Bergen og omegn<br>Innovasjon Norge · Demokratisk deltakelse<br><time datetime=\"2026-07-14\">14. juli 2026</time>",
  body: <<~BODY,
    <h2>1. Sammendrag</h2>
    <p>Ditt Parti er en digital plattform for lokal politisk mobilisering i Bergen og Vestland. Vi gjør det enkelt for borgere å finne kandidater, forstå programmer og delta i folkeavstemninger uten å forlate nabolaget.</p>
    <p>Plattformen bygger på pub4 sin Rails- og MASTER-stack: verifisert identitet, transparent finansiering og HTU-klar dokumentasjon for legater og offentlige tilskudd.</p>
    <h2>2. Problem</h2>
    <p>Lav valgdeltakelse og fragmentert informasjon gjør det vanskelig for unge og nye innbyggere å engasjere seg. Eksisterende partier kommuniserer primært top-down.</p>
    <h2>3. Løsning</h2>
    <p>Hyperlokale «partirom» per bydel med kandidatprofiler, debattstrømmer og åpne budsjettforslag. MASTER AI hjelper med å oversette politisk jargon til klart norsk.</p>
    <h2>4. Finansiering</h2>
    <table>
      <tr><td>1.</td><td>Innovasjon Norge — NOK 2,5M (MVP + pilot i Åsane, Fana, Sentrum)</td></tr>
      <tr><td>2.</td><td>Legathåndboken Bergen — NOK 500k (tilgjengelighet og WCAG)</td></tr>
      <tr><td>3.</td><td>Egenkapital og crowdfundet medlemskap — NOK 750k</td></tr>
    </table>
    <h2>5. Påstander</h2>
    <table>
      <tr><td>1.</td><td>Øke lokal valgdeltakelse med 15 prosentpoeng innen 2028.</td></tr>
      <tr><td>2.</td><td>Publisere alle utgifter og Møter i sanntid.</td></tr>
      <tr><td>3.</td><td>Åpne API for forskning og journalistikk.</td></tr>
    </table>
  BODY
  outfile: "ditt_parti.html"
)

# --- ilumi_gravferd (new) ---
wrap_plan(
  title: "Ilumi Gravferd — Forretningsplan",
  meta: "Ilumi Gravferd AS · Bergen og Vestland<br>Innovasjon Norge · Verdig minnesmerke<br><time datetime=\"2026-07-14\">14. juli 2026</time>",
  body: <<~BODY,
    <h2>1. Sammendrag</h2>
    <p>Ilumi Gravferd tilbyr rolige, lysbaserte minneseremonier og digital gravpleie for familier i Bergen og omegn. Vi kombinerer håndverk, naturmaterialer og MASTER-drevet planlegging for å redusere stress i en sårbar fase.</p>
    <h2>2. Problem</h2>
    <p>Tradisjonelle byråer er dyre, lite transparente og tilpasser seg dårlig sekulære og flerkulturelle familier. Mange opplever informasjonsmangel når de trenger hjelp raskt.</p>
    <h2>3. Løsning</h2>
    <p>Fastpris-pakker med tydelig HTU-dokumentasjon, lokale leverandørnettverk og en digital «minnebok» som arvinger kan dele. Postpro og Repligen genererer respektfulle portretter og seremonibilder etter samtykke.</p>
    <h2>4. Finansiering</h2>
    <table>
      <tr><td>1.</td><td>Innovasjon Norge — NOK 1,8M (digital plattform + pilot med to samarbeidende byrå)</td></tr>
      <tr><td>2.</td><td>Legathåndboken Bergen — NOK 400k (lavterskel rådgivning for lavinntektsfamilier)</td></tr>
      <tr><td>3.</td><td>Driftskreditt og forhåndsbetalte familiepakker — NOK 600k</td></tr>
    </table>
    <h2>5. Påstander</h2>
    <table>
      <tr><td>1.</td><td>Fastpris uten skjulte tillegg for standardpakker.</td></tr>
      <tr><td>2.</td><td>24-timers digital rådgivningslinje i Bergen.</td></tr>
      <tr><td>3.</td><td>Åpen prisliste og leverandørkjede for pårørende.</td></tr>
    </table>
  BODY
  outfile: "ilumi_gravferd.html"
)

# --- index ---
File.write(File.join(ROOT, "index.html"), <<~HTML)
  <!DOCTYPE html>
  <html lang="no">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>pub4 — Forretningsplaner</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400;0,500;0,600;1,400;1,500&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="htu/htu.css">
  </head>
  <body>
    <article>
      <img src="htu/bergen.svg" alt="" class="logo">
      <header>
        <h1>Forretningsplaner</h1>
        <p class="meta">pub4 · Bergen · Innovasjon Norge &amp; legathåndboken<br>Alle planer følger HTU-brev layout eksakt.</p>
      </header>
      <div class="content">
        <h2>Planer</h2>
        <table>
          <tr><td>1.</td><td><a href="syre_shoes.html">SYRE™ sko</a></td></tr>
          <tr><td>2.</td><td><a href="ditt_parti.html">Ditt Parti</a></td></tr>
          <tr><td>3.</td><td><a href="ilumi_gravferd.html">Ilumi Gravferd</a></td></tr>
          <tr><td>4.</td><td><a href="norwegianhedge.html">Norwegian Hedge</a></td></tr>
          <tr><td>5.</td><td><a href="pub_healthcare.html">pub.healthcare</a></td></tr>
          <tr><td>6.</td><td><a href="pub_attorney.html">pub.attorney</a> (→ ai.brgen.no)</td></tr>
        </table>
        <h2>HTU-referanse</h2>
        <table>
          <tr><td>·</td><td><a href="htu/layout-1.html">HTU layout 1 — klassisk sentrert</a></td></tr>
          <tr><td>·</td><td><a href="htu/layout-2.html">HTU layout 2 — kursiv tittel</a></td></tr>
        </table>
      </div>
    </article>
  </body>
  </html>
HTML
puts "wrote index.html"