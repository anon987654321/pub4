# frozen_string_literal: true

require "yaml"
require_relative "lib/bplan/constants"
require_relative "lib/bplan/html"

module FundingHelpers
  PLAN_ORDER = Bplan::Constants::PLAN_ORDER
  MASTER_BLURB = <<~TXT.strip.freeze
    MASTER er et selvrefinerende, konstitusjonelt styrt AI-kodingsystem i Ruby. Gjennom multi-agent debatt,
    kontinuerlig selvkritikk og iterative forbedringsløkker analyserer, refaktorerer og hever systemet kvaliteten
    på kode — inkludert sin egen — innenfor klare etiske og sikkerhetsmessige rammer inspirert av OpenBSD.
  TXT

  RAILS_BLURB = <<~TXT.strip.freeze
    RAILS/ inneholder deploybare Rails 8-apper (brgen.no, amber.brgen.no, bsdports.org m.fl.) som MASTER
    utvikler og forbedrer. BPLAN dokumenterer og søker støtte — det er en egen app, ikke en del av RAILS/.
  TXT

  TRACK_NEED = {
    "innovasjon" => "Norske småmiljøer trenger produksjonsklar programvare uten å outsource til utenlandsk SaaS — med målbar innovasjon og norsk datakontroll.",
    "helse" => "Helse- og omsorgssektoren trenger verktøy som effektiviserer samhandling uten å erstatte klinisk skjønn eller kompromittere personvern.",
    "samfunn" => "Lokalt demokrati og fellesskap i Bergen trenger trygge, tilgjengelige digitale flater — ikke sentraliserte plattformer uten moderering.",
    "klima" => "Forbrukere trenger praktiske verktøy for å bruke det de har lengre — ikke nok en grønn app uten målbar effekt.",
    "sikkerhet" => "Offentlig sektor og maritime miljøer trenger sporbar, minimal-privilege infrastruktur — ikke blind tillit til utenlandsk sky.",
    "produkt" => "Bergen trenger lokal produksjonskompetanse og prototyping før skala — ikke masseimport uten kvalitetskontroll.",
    "finans" => "Norske aktører trenger åpen risikomodellering og læringsverktøy — innenfor Finanstilsynets rammer, ikke uregulert spekulasjon.",
    "sosial" => "Pårørende i sorg trenger forutsigbarhet, verdighet og fastpris — ikke salgstaktikk i en sårbar situasjon.",
    "civic" => "Borgere trenger forståelig norsk veiledning for brev og skjema — ikke juridisk sjargong eller dyr konsulenttime.",
    "kultur" => "Bergen trenger lokalt medieinnhold og visuell produksjon med respekt for medvirkning — ikke bare algoritme-støy.",
    "bolig" => "Stabil bolig i Bergen krever Startlån, Husbanken og ærlig dokumentasjon — ikke fantasibeløp fra klassiske legater.",
  }.freeze

  TECH_TRACKS = %w[innovasjon helse samfunn sikkerhet].freeze
  PROJECT_ALIASES = {
    "pub.healthcare" => "pub_healthcare",
    "pub4" => "master",
    "master+pub.healthcare" => "pub_healthcare",
    "master+rails" => "master",
    "master+bsdports" => "bsdports",
    "rails" => "brgen",
    "norwegianhedge" => "norwegian_hedge",
    "ilumi" => "ilumi_gravferd",
    "personal" => "personal",
  }.freeze

  module_function

  def load_funding(root)
    YAML.load_file(File.join(root, "funding.yml"))
  end

  def resolve_venture(project)
    key = project.to_s.strip
    PROJECT_ALIASES.fetch(key, key.tr(".", "_").tr("+", "_").gsub(/__+/, "_"))
  end

  def venture_data(funding, project_or_venture)
    key = resolve_venture(project_or_venture)
    funding["ventures"][key]
  end

  def fmt(n)
    return "0" unless n
    n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1 ').reverse.strip
  end

  def venture_breakdown(venture, funding)
    econ = funding["economics"]
    v = funding["ventures"][venture] || {}
    return v["breakdown"].map(&:dup) if v["breakdown"]

    lines = econ["breakdown"].map(&:dup)
    target = v["project_total_nok"].to_i.positive? ? v["project_total_nok"].to_i : econ["annual_dev_project_realistic_nok"].to_i
    base = lines.sum { |l| l["nok"].to_i }
    return lines if base.zero? || base == target

    ratio = target.to_f / base
    scaled = lines.map do |line|
      { "item" => line["item"], "nok" => (line["nok"].to_i * ratio).round(-3) }
    end
    drift = target - scaled.sum { |l| l["nok"].to_i }
    scaled.last["nok"] = scaled.last["nok"].to_i + drift if drift.nonzero? && scaled.any?
    scaled
  end

  def budget_table(venture, funding)
    return bolig_budget_block(funding) if venture == "bolig_bergen"
    return personal_budget_block(funding) if venture == "personal"

    econ = funding["economics"]
    v = funding["ventures"][venture] || {}
    total = v["project_total_nok"].to_i.positive? ? v["project_total_nok"] : econ["annual_dev_project_realistic_nok"]
    legat = v["ask_legat_nok"]
    inn = v["ask_in_nok"]
    breakdown = venture_breakdown(venture, funding)

    cost_rows = breakdown.map do |line|
      ["", "#{line['item']} — NOK #{fmt(line['nok'])}"]
    end
    cost_rows << ["·", "<strong>Sum</strong> — NOK #{fmt(breakdown.sum { |l| l['nok'].to_i })}"]

    fin_cells = [["", "Egeninnsats og eksisterende kodebase (MASTER/RAILS)"]]
    if legat.to_i.positive?
      fin_cells << ["", "Legat/stipend — søkt NOK #{fmt(legat)}"]
    end
    if inn.to_i.positive?
      fin_cells << ["", "Innovasjon Norge / offentlig støtte — mål NOK #{fmt(inn)} (#{ask_in_explainer(venture, funding)})"]
    end
    fin_cells << ["", "SkatteFUNN — skattefradrag på FoU, ikke kontant utbetaling"]

    cashflow = cashflow_note_block(venture, funding)

    <<~HTML
      <h2>Budsjett (realistisk, 12 mnd)</h2>
      <p><strong>Prosjektsum:</strong> NOK #{fmt(total)}. Enkeltpersonforetak, Bergen.</p>
      <table>
        #{Bplan::Html.format_table_rows(cost_rows, headers: %w[# Post], numbered: true)}
      </table>
      <h3>Finansieringsplan</h3>
      <table>
        #{Bplan::Html.format_table_rows(fin_cells, headers: %w[# Kilde], numbered: true)}
      </table>
      <p class="meta" style="margin-top:1rem;font-size:0.9rem;">#{econ['skattefunn_note']}</p>
      #{cashflow}
    HTML
  end

  def wholesome_block(venture, funding)
    v = funding["ventures"][venture]
    return "" unless v

    pitch = v["wholesome_pitch"].to_s.strip
    note = v["note"]
    dels = v["deliverables"] || []
    trl = v["trl"]

    html = "<h2>2. Hvorfor dette er samfunnsnyttig</h2>\n<p>#{pitch}</p>\n"
    html += "<p><em>#{note}</em></p>\n" if note
    html += "<p class=\"meta\">TRL: #{trl}</p>\n" if trl
    html += "<h2>3. Leveranser</h2>\n<ul>\n"
    dels.each { |d| html += "  <li>#{d}</li>\n" }
    html += "</ul>\n"
    html
  end

  def summary_block(venture, funding, extra: nil)
    v = funding["ventures"][venture]
    return "" unless v

    intro = case venture
            when "bolig_bergen"
              "<strong>#{v['title']}</strong> — personlig boligspor i Bergen. Helt separat fra innovasjonsprosjekter."
            when "personal"
              "<strong>#{v['title']}</strong> — ærlig personlig søknad. Ikke pakket som teknologiprosjekt."
            else
              "<strong>#{v['title']}</strong> — PubHealthcare, Bergen. MASTER utvikler; RAILS/ deployer apper."
            end
    html = "<h2>1. Sammendrag</h2>\n<p>#{intro}</p>\n"
    html += en_summary_block(venture, funding)
    html += "<p><em>#{v['note']}</em></p>\n" if v["note"] && %w[bolig_bergen personal norwegian_hedge].include?(venture)
    html += "<p>#{extra}</p>\n" if extra
    html
  end

  def deadline_calendar_block(funding, limit: nil)
    rows = funding.fetch("deadlines", []).sort_by { |d| d["date"].to_s }
    rows = rows.first(limit) if limit
    today = funding["generated"].to_s

    body = rows.map.with_index(1) do |d, i|
      span = if d["end_date"]
               "#{d['date']} – #{d['end_date']}"
             else
               d["date"].to_s
             end
      urgent = d["date"].to_s <= today && (d["end_date"].nil? || d["end_date"].to_s >= today)
      tag = urgent ? " <span class=\"meta\">(åpen nå)</span>" : ""
      "<tr><td>#{i}.</td><td>#{span}#{tag}</td><td>#{d['funder']}</td><td>#{d['track']}</td><td>#{d['action']}</td></tr>"
    end.join("\n        ")

    <<~HTML
      <h2>Fristkalender</h2>
      <p class="meta">Verifiser alltid på giverens nettside før sending. <code>ruby build_plans.rb</code> regenererer fra funding.yml.</p>
      <table>
        <tr><td>#</td><td>Frist</td><td>Giver</td><td>Spor</td><td>Handling</td></tr>
        #{body}
      </table>
    HTML
  end

  def portfolio_summary_block(funding)
    p = funding.fetch("portfolio", {})
    econ = funding["economics"]
    ceil = p.fetch("realistic_ceiling_nok", {})
    sl = p.fetch("startlan_bergen", {})
    rules = p.fetch("anti_double_dip", []).map.with_index(1) { |r, i| "<tr><td>#{i}.</td><td>#{r}</td></tr>" }.join("\n        ")
    ventures = funding["ventures"].reject { |k, _| %w[personal bolig_bergen].include?(k) }
    legat_sum = ventures.sum { |_, v| v["ask_legat_nok"].to_i }
    in_max = ventures.map { |_, v| v["ask_in_nok"].to_i }.max

    ceiling_rows = [
      ["Legater (sum alle idéer, ikke dobbelt)", "NOK #{fmt(ceil['legat_sum_all_ventures'] || legat_sum)}"],
      ["Primær innovasjon (IN/FR, én kanal)", "NOK #{fmt(ceil['innovasjon_primary'] || in_max)}"],
      ["SkatteFUNN (skattefradrag)", "NOK #{fmt(ceil['skattefunn_credit'])}"],
      ["Levekostnad / mnd minimum", "NOK #{fmt(ceil['monthly_living'] || econ['monthly_minimum_living_nok'])}"],
      ["Startlån-tilskudd (kommune)", "#{sl['tilskudd_typical_nok'] || '250000–500000'} NOK"],
    ]

    <<~HTML
      <h2>Portefølje — konvergens</h2>
      <p class="meta">Én sannhetskilde (funding.yml v#{p['convergence_version'] || 1}). Tall er realistiske for solo-utvikler i Bergen.</p>
      <table>
        #{Bplan::Html.format_table_rows(ceiling_rows, headers: %w[Post Realistisk\ tak])}
      </table>
      #{legat_sum_explainer_block(funding)}
      <h3>Anti-dobbelsøk</h3>
      <table>
        #{rules}
      </table>
      <p class="meta">Startlån: #{sl['søknad'] || 'fortløpende'} · #{sl['kontakt']}</p>
    HTML
  end

  def letter_sections(project:, deliverables:, angle:, funding:, funder_type: :legat, funder_id: nil)
    venture = resolve_venture(project)
    v = funding["ventures"][venture] || {}
    track = v["track"] || "innovasjon"
    pitch = v["wholesome_pitch"] || "MASTER + RAILS for norsk digital suverenitet."
    need = TRACK_NEED[track] || TRACK_NEED["innovasjon"]

    tech = if TECH_TRACKS.include?(track)
             "<p>#{MASTER_BLURB}</p>\n<p>#{RAILS_BLURB}</p>"
           elsif track == "bolig"
             ""
           else
             "<p><strong>Metode:</strong> MASTER og Rails der relevant — fokus på leveransene under, ikke hype.</p>"
           end

    solution = if TECH_TRACKS.include?(track)
                 <<~HTML
                   <p><strong>MASTER (direkte):</strong> Selvforbedrende multi-agent arkitektur med konstitusjonelle prinsipper og OpenBSD-inspirert sikkerhet.</p>
                   <p><strong>RAILS (indirekte):</strong> Rails 8-applikasjoner med Hotwire, Falcon, SQLite/Solid Queue — reelle tjenester.</p>
                 HTML
               else
                 "<p><strong>Løsning:</strong> #{pitch}</p>"
               end

    <<~BODY
      <h2>1. Sammendrag</h2>
      <p>Jeg søker støtte til <strong>#{v['title'] || project}</strong>. #{pitch}</p>
      #{tech}
      <p>#{angle}</p>

      <h2>2. Bakgrunn og behov</h2>
      <p>#{need}</p>

      <h2>3. Løsning og innovasjon</h2>
      #{solution}

      <h2>4. Mål og leveranser</h2>
      <ul>
        #{deliverables.map { |d| "<li>#{d}</li>" }.join("\n        ")}
      </ul>

      #{legat_budget_section(venture, funding, funder_type: funder_type, funder_id: funder_id)}

      <h2>6. Påstander</h2>
      #{claims_block(venture, funding).sub("<h2>Påstander</h2>", "").strip}
    BODY
  end

  def bolig_budget_block(funding)
    sl = funding.dig("portfolio", "startlan_bergen") || {}
    rows = [
      ["", "Startlån (Husbanken/Boligkontoret) — fortløpende søknad"],
      ["", "Tilskudd ved lav inntekt — typisk #{sl['tilskudd_typical_nok'] || '250000–500000'} NOK"],
      ["", "Førstegang: min. #{sl['egenkapital_førstegang_prosent'] || 5} % egenkapital + #{sl['bank_avslag_minimum'] || 3} bankavslag"],
      ["", "Personlegater (Gunvor Minde, Zuccarelli, vanskeligstilte) — brofinansiering 10–50k"],
    ]
    <<~HTML
      <h2>Budsjett — boligspor (ikke FoU)</h2>
      <p>Dette er <em>ikke</em> et utviklingsbudsjett. Finansiering skjer via Startlån, ev. tilskudd og personlegater.</p>
      <table>
        #{Bplan::Html.format_table_rows(rows, headers: %w[# Kanal], numbered: true)}
      </table>
      <p class="meta">#{funding.dig('economics', 'bolig_note')}</p>
      #{attachment_checklist_block('startlan', funding)}
    HTML
  end

  def personal_budget_block(funding)
    personal_use_of_funds_block(funding)
  end

  def claims_block(venture, funding)
    v = funding["ventures"][venture]
    claims = v&.fetch("claims", nil) || default_claims(venture)
    rows = claims.map.with_index(1) { |c, i| "<tr><td>#{i}.</td><td>#{c}</td></tr>" }.join("\n        ")
    <<~HTML
      <h2>Påstander</h2>
      <table>
        #{rows}
      </table>
    HTML
  end

  def default_claims(venture)
    case venture
    when "bolig_bergen", "personal"
      [
        "Egen beboelse og ærlig dokumentasjon i Bergen.",
        "Støtte brukes til godkjente formål med kvitteringer.",
        "Separat fra innovasjonsprosjekter — ikke dobbeltsøk for samme utgift.",
      ]
    when "norwegian_hedge"
      [
        "Programvare for læring og risikoanalyse — ikke uregulert fond.",
        "Finanstilsynet og lisenskrav vurderes før markedslansering.",
        "Åpen metodikk og revisjonert kode.",
      ]
    else
      [
        "All støtte brukes til godkjent formål med etterrettelig dokumentasjon.",
        "Leveranser dokumenteres i tråd med givers krav.",
        "Prosjektet styrker norsk digital suverenitet og velferdsteknologi.",
      ]
    end
  end

  def funder_realistic_row(f)
    realistic = f["realistic_for_us_nok"]
    realistic_cell = realistic.is_a?(Integer) ? "NOK #{fmt(realistic)}" : (realistic || "—")
    "<tr><td>#{f['name']}</td><td>#{f['type']}</td><td>#{f['typical_nok']}</td><td>#{realistic_cell}</td></tr>"
  end

  def funders_table(funding, venture: nil)
    funders = funding["funders"]
    funders = funders.select { |f| (f["fit"] || []).include?(venture) } if venture
    rows = funders.map do |f|
      realistic = f["realistic_for_us_nok"]
      realistic_cell = realistic.is_a?(Integer) ? "NOK #{fmt(realistic)}" : (realistic || "—")
      [f["name"], f["type"], f["typical_nok"], realistic_cell]
    end
    <<~HTML
      <h2>Relevante finansieringskilder</h2>
      <table>
        #{Bplan::Html.format_table_rows(rows, headers: %w[Giver Type Typisk Realistisk\ for\ oss])}
      </table>
    HTML
  end

  def legat_ask_text(venture, funding, override: nil)
    amount = override
    amount ||= funding.dig("ventures", venture, "ask_legat_nok")
    amount ||= funding.dig("ventures", "personal", "ask_legat_nok")
    if amount.to_i.positive?
      "NOK #{fmt(amount)} (typisk legat/stipend — ikke millionbeløp)"
    else
      "Ikke primært legatkanal — se Innovasjon Norge, kommune eller SkatteFUNN"
    end
  end

  def innovasjon_ask_text(venture, funding, funder_id: nil)
    v = funding["ventures"][venture]
    amount = v&.dig("ask_in_nok")
    if funder_id
      f = funding["funders"].find { |x| x["id"] == funder_id }
      amount = f["realistic_for_us_nok"] if f&.dig("realistic_for_us_nok").is_a?(Integer)
    end
    return "Etter utlysning og egenandel" unless amount.to_i.positive?
    "NOK #{fmt(amount)} (mål — krever business case, pilotkunde og egenandel)"
  end

  def skattefunn_text(funding)
    funding.dig("economics", "skattefunn_note").to_s
  end

  def bolig_channels_block(funding)
    econ = funding["economics"]
    sl = funding.dig("portfolio", "startlan_bergen") || {}
    <<~HTML
      <h2>2. Kanaler (ærlig boligspor)</h2>
      <table>
        <tr><td>1.</td><td>Startlån — #{sl['søknad'] || 'fortløpende via Husbanken'}</td></tr>
        <tr><td>2.</td><td>Tilskudd ved lav inntekt — typisk #{sl['tilskudd_typical_nok'] || '250000–500000'} NOK</td></tr>
        <tr><td>3.</td><td>Førstegang: #{sl['egenkapital_førstegang_prosent'] || 5} % egenkapital + #{sl['bank_avslag_minimum'] || 3} bankavslag</td></tr>
        <tr><td>4.</td><td>Bergen bys stiftelse til økonomisk vanskeligstilte</td></tr>
        <tr><td>5.</td><td>Gunvor Mindes legat · Zuccarellostiftelsen (brofinansiering 10–50k)</td></tr>
      </table>
      <p><em>#{econ['bolig_note']}</em></p>
      <p class="meta">Kontakt: #{sl['kontakt'] || 'boligkontoret@bergen.kommune.no'}</p>
    HTML
  end

  def personal_use_of_funds_block(funding)
    amount = funding.dig("ventures", "personal", "ask_legat_nok")
    breakdown = venture_breakdown("personal", funding)
    rows = if breakdown.any?
             breakdown.map { |line| ["", "#{line['item']} — NOK #{fmt(line['nok'])}"] }
           else
             [
               ["", "Husleie og boligutgifter i Bergen"],
               ["", "Nødvendig utstyr for inntektsgenererende arbeid"],
               ["", "Mat, transport og grunnleggende levekostnader"],
             ]
           end
    <<~HTML
      <h2>3. Bruk av midler</h2>
      <table>
        #{Bplan::Html.format_table_rows(rows, headers: %w[# Post], numbered: true)}
      </table>
      <p class="meta">Realistisk legatstørrelse: ca. NOK #{fmt(amount)} — brofinansiering, ikke boligkjøp.</p>
      #{attachment_checklist_block('gunvor_minde', funding)}
    HTML
  end

  def legat_budget_section(venture, funding, funder_type: :legat, funder_id: nil)
    v = funding["ventures"][venture]
    return personal_use_of_funds_block(funding) if venture == "personal"

    amount_line = case funder_type
                  when :innovasjon then innovasjon_ask_text(venture, funding, funder_id: funder_id)
                  when :skattefunn then skattefunn_text(funding)
                  when :forskning then innovasjon_ask_text(venture, funding, funder_id: "forskningsradet")
                  else legat_ask_text(venture, funding)
                  end

    total = v&.dig("project_total_nok") || funding.dig("economics", "annual_dev_project_realistic_nok")
    breakdown = venture_breakdown(venture, funding)
    cost_rows = breakdown.reject { |l| l["item"].to_s.include?("Buffer") }.first(4).map.with_index(1) do |line, i|
      "<tr><td>#{i}.</td><td>#{line['item']} — NOK #{fmt(line['nok'])}</td></tr>"
    end.join("\n        ")

    <<~HTML
      <h2>5. Budsjett og finansiering</h2>
      <p><strong>Søkt beløp:</strong> #{amount_line}</p>
      <p><strong>Prosjektramme (12 mnd):</strong> NOK #{fmt(total)} — detaljert i forretningsplan.</p>
      <table>
        #{cost_rows}
      </table>
      <p class="meta">Klassiske legater: typisk #{funding.dig('economics', 'legat_typical_range_nok')} NOK.</p>
    HTML
  end

  def legat_sum_explainer_block(funding)
    text = funding.dig("portfolio", "legat_sum_explainer").to_s.strip
    return "" if text.empty?

    "<p class=\"meta\"><em>#{text}</em></p>\n"
  end

  def attachment_checklist_block(funder_id, funding)
    f = funding["funders"].find { |x| x["id"] == funder_id.to_s }
    items = f&.fetch("attachment_checklist", nil)
    return "" unless items&.any?

    rows = items.map { |item| ["", item] }
    <<~HTML
      <h3>Vedlegg — #{f['name']}</h3>
      <table>
        #{Bplan::Html.format_table_rows(rows, headers: %w[# Vedlegg], numbered: true)}
      </table>
    HTML
  end

  def en_summary_block(venture, funding)
    summary = funding.dig("ventures", venture, "en_summary").to_s.strip
    return "" if summary.empty?

    "<p class=\"meta\"><strong>EN:</strong> #{summary}</p>\n"
  end

  def cashflow_note_block(venture, funding)
    note = funding.dig("ventures", venture, "cashflow_note").to_s.strip
    return "" if note.empty?

    "<p class=\"meta\"><strong>Likviditet:</strong> #{note}</p>\n"
  end

  def ask_in_explainer(venture, funding)
    v = funding["ventures"][venture] || {}
    inn = v["ask_in_nok"].to_i
    return "egenandel etter utlysning" unless inn.positive?

    "egenandel krav — book IN-rådgiver, ikke masse-e-post"
  end

  def fun_wholesome_table(funding)
    rows = funding.fetch("fun_wholesome", []).map.with_index(1) do |item, i|
      realistic = item["realistic"] ? "Ja" : "Nei (meta)"
      ask = item["ask_nok"].to_i.positive? ? "NOK #{fmt(item['ask_nok'])}" : "—"
      "<tr><td>#{i}.</td><td>#{item['name']}</td><td>#{realistic}</td><td>#{ask}</td><td>#{item['wholesome_angle']}</td></tr>"
    end.join("\n        ")
    <<~HTML
      <h2>Wholesome idé-katalog (meta → ekte kanaler)</h2>
      <p>Disse er ærlige vinkler — søk reelle givere i kolonnen «Realistisk kanal» i funding.yml.</p>
      <table>
        <tr><td>#</td><td>Idé</td><td>Realistisk?</td><td>Beløp</td><td>Vinkel</td></tr>
        #{rows}
      </table>
    HTML
  end
end