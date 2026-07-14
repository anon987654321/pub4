# frozen_string_literal: true

require_relative "constants"

module Bplan
  module Html
    TABLE_SCRIPT = <<~JS
      document.querySelectorAll('.content table').forEach(function(t) {
        t.setAttribute('role', 'table');
      });
    JS

    module_function

    def th_cells(labels)
      labels.map { |label| "<th scope=\"col\">#{label}</th>" }.join
    end

    def table_script
      TABLE_SCRIPT
    end

    def escape_html(text)
      text.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub('"', "&quot;")
    end

    def meta_description(text)
      "<meta name=\"description\" content=\"#{escape_html(text)}\">"
    end

    def disclaimer_paragraph
      "<p class=\"meta disclaimer\">#{Constants::GLOBAL_DISCLAIMER}</p>"
    end

    def prev_next_nav(slug, order:, base_path: "")
      idx = order.index(slug)
      return "" unless idx

      prev_slug = order[idx - 1] if idx.positive?
      next_slug = order[idx + 1] if idx < order.length - 1
      parts = []
      parts << "<a href=\"#{base_path}#{prev_slug}.html\">← Forrige</a>" if prev_slug
      parts << "<a href=\"#{base_path}index.html\">Oversikt</a>"
      parts << "<a href=\"#{base_path}#{next_slug}.html\">Neste →</a>" if next_slug
      "<nav class=\"plan-nav meta\" aria-label=\"Navigasjon\">#{parts.join(" · ")}</nav>"
    end

    def plan_html(title:, description:, meta:, body:, slug:, order: Constants::PLAN_ORDER)
      <<~HTML
        <!DOCTYPE html>
        <html lang="#{Constants::LANG}">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>#{title}</title>
          #{meta_description(description)}
          <link rel="preconnect" href="https://fonts.googleapis.com">
          <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
          <link href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400;0,500;0,600;1,400;1,500&display=swap" rel="stylesheet">
          <link rel="stylesheet" href="#{Constants::HTU_CSS}">
        </head>
        <body>
          <article data-plan="#{slug}">
            <img src="#{Constants::LOGO}" alt="" class="logo">
            <header>
              <h1>#{title}</h1>
              <p class="meta">#{meta}<br><time datetime="#{Constants::DATE_ISO}">#{Constants::DATE}</time></p>
            </header>
            <div class="content">
              #{body}
            </div>
            #{prev_next_nav(slug, order: order)}
            <footer>
              <p>Med vennlig hilsen<br><strong>#{Constants::FOOTER}</strong></p>
              #{disclaimer_paragraph}
            </footer>
          </article>
          <script>
        #{TABLE_SCRIPT}
          </script>
        </body>
        </html>
      HTML
    end

    def wrap_letter(title:, description:, meta:, body:, funder_id: nil, css_href: Constants::HTU_CSS, logo_src: Constants::LOGO, footer_name: Constants::APPLICANT[:footer])
      funder_attr = funder_id ? " data-funder-id=\"#{funder_id}\"" : ""
      <<~HTML
        <!DOCTYPE html>
        <html lang="#{Constants::LANG}">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>#{title}</title>
          #{meta_description(description)}
          <link rel="preconnect" href="https://fonts.googleapis.com">
          <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
          <link href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400;0,500;0,600;1,400;1,500&display=swap" rel="stylesheet">
          <link rel="stylesheet" href="#{css_href}">
        </head>
        <body>
          <article#{funder_attr}>
            <img src="#{logo_src}" alt="" class="logo">
            <header>
              <h1>#{title}</h1>
              <p class="meta">#{meta}</p>
            </header>
            <div class="content">
              #{body}
            </div>
            <footer>
              <p>Med vennlig hilsen<br><strong>#{footer_name}</strong></p>
              #{disclaimer_paragraph}
            </footer>
          </article>
          <script>
        #{TABLE_SCRIPT}
          </script>
        </body>
        </html>
      HTML
    end

    def format_table_rows(rows, headers: nil, numbered: false)
      out = +""
      if headers&.any?
        out << "<thead><tr>#{th_cells(headers)}</tr></thead>\n<tbody>\n"
      else
        out << "<tbody>\n"
      end
      rows.each_with_index do |row, i|
        cells = row.is_a?(Array) ? row.dup : [row]
        if numbered
          cells[0] = if cells.first.to_s == "·"
                       "·"
                     elsif cells.first.to_s.strip.empty?
                       "#{i}."
                     else
                       cells.first
                     end
        end
        out << "<tr>#{cells.map { |c| "<td>#{c}</td>" }.join}</tr>\n"
      end
      out << "</tbody>"
      out
    end

    def wrap_document(title:, meta:, body:, slug: nil, type: "plan")
      description = "#{title}. #{meta.to_s.gsub('<br>', ' — ')} Bergen, #{Constants::DATE}."
      case type
      when "legat"
        wrap_letter(title: title, description: description, meta: meta, body: body, funder_id: slug)
      else
        plan_html(title: title, description: description, meta: meta, body: body, slug: slug || "index")
      end
    end

    def to_text(path_or_html)
      html = path_or_html.include?("<") ? path_or_html : File.read(path_or_html)
      html.gsub(/<br\s*\/?>/i, "\n")
          .gsub(%r{</p>}i, "\n\n")
          .gsub(%r{</h[1-6]>}i, "\n\n")
          .gsub(/<li>/i, "• ")
          .gsub(/<[^>]+>/, "")
          .gsub("&nbsp;", " ")
          .gsub("&amp;", "&")
          .gsub("&lt;", "<")
          .gsub("&gt;", ">")
          .gsub(/\n{3,}/, "\n\n")
          .strip
    end

    def legat_sum_explainer(funding, fmt: nil)
      fmt ||= ->(n) { n.to_s }
      p = funding.fetch("portfolio", {})
      econ = funding["economics"]
      ceil = p.fetch("realistic_ceiling_nok", {})
      ventures = funding["ventures"].reject { |k, _| %w[personal bolig_bergen].include?(k) }
      raw_sum = ventures.sum { |_, v| v["ask_legat_nok"].to_i }

      <<~HTML
        <h3>Legatsum — hvorfor ikke bare addere?</h3>
        <p class="meta">
          Summen av alle <code>ask_legat_nok</code> per idé er NOK #{fmt.call(raw_sum)} — men det er <em>ikke</em> et realistisk utbetalingsmål.
          Klassiske legater er 5–75k per søknad; anti-dobbelsøk og kanalvalg begrenser faktisk likviditet.
        </p>
        <table>
          <tr><td>Sum alle idé-asks (teoretisk)</td><td>NOK #{fmt.call(raw_sum)}</td></tr>
          <tr><td>Realistisk tak (portefølje)</td><td>NOK #{fmt.call(ceil['legat_sum_all_ventures'] || raw_sum)}</td></tr>
          <tr><td>Typisk enkeltlegat</td><td>#{econ['legat_typical_range_nok']} NOK</td></tr>
        </table>
      HTML
    end

    def plans_index_html(plan_defs:, funding:, helpers:)
      idea_rows = plan_defs.map.with_index(1) do |p, i|
        "<tr><td>#{i}.</td><td><a href=\"#{p[:slug]}.html\">#{p[:title]}</a></td></tr>"
      end.join("\n        ")

      <<~HTML
        <!DOCTYPE html>
        <html lang="#{Constants::LANG}">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>BPLAN — pub4</title>
          #{meta_description("Forretningsplaner og legatsøknader for MASTER/RAILS-prosjekter i Bergen.")}
          <link rel="preconnect" href="https://fonts.googleapis.com">
          <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
          <link href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400;0,500;0,600;1,400;1,500&display=swap" rel="stylesheet">
          <link rel="stylesheet" href="#{Constants::HTU_CSS}">
        </head>
        <body>
          <article>
            <img src="#{Constants::LOGO}" alt="" class="logo">
            <header>
              <h1>BPLAN</h1>
              <p class="meta">#{plan_defs.size} ideer · én HTML per idé · Bergen<br><time datetime="#{Constants::DATE_ISO}">#{Constants::DATE}</time></p>
            </header>
            <div class="content">
              <h2>Forretningsplaner</h2>
              <table>
                #{idea_rows}
              </table>
              #{helpers.portfolio_summary_block(funding)}
              #{legat_sum_explainer(funding, fmt: helpers.method(:fmt))}
              #{helpers.deadline_calendar_block(funding)}
              #{helpers.fun_wholesome_table(funding)}
              <h2>Legatsøknader</h2>
              <table>
              <tr><td>→</td><td><a href="legats/index.html">Alle legater</a> — <code>ruby build_legats.rb</code></td></tr>
              <tr><td>→</td><td>BPLAN/rails: <code>cd rails && bundle exec rails server</code> (port 39282, egen app)</td></tr>
            </table>
            <p class="meta"><code>ruby build_plans.rb</code> · <code>ruby build_legats.rb</code> · kanon: <code>funding.yml</code></p>
            </div>
            <footer>
              #{disclaimer_paragraph}
            </footer>
          </article>
          <script>
        #{TABLE_SCRIPT}
          </script>
        </body>
        </html>
      HTML
    end

    def legats_index_html(manifest_entries:, funding:, helpers:)
      rows = manifest_entries.map.with_index(1) do |e, i|
        track = e["track"]
        deadline = e["deadline"]
        sendable = e["sendable"] ? "" : " <span class=\"meta\">(ikke auto-send)</span>"
        "<tr><td>#{i}.</td><td><a href=\"#{e['file'].sub('legats/', '')}\">#{e['funder']}</a>#{sendable}</td><td>#{track}</td><td>#{deadline}</td></tr>"
      end.join("\n        ")

      <<~HTML
        <!DOCTYPE html>
        <html lang="#{Constants::LANG}">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>pub4 — Legatsøknader</title>
          #{meta_description("Legatsøknader for MASTER/RAILS-prosjekter — Bergen og Norge.")}
          <link rel="preconnect" href="https://fonts.googleapis.com">
          <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
          <link href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400;0,500;0,600;1,400;1,500&display=swap" rel="stylesheet">
          <link rel="stylesheet" href="../#{Constants::HTU_CSS}">
        </head>
        <body>
          <article>
            <img src="../#{Constants::LOGO}" alt="" class="logo">
            <header>
              <h1>Legatsøknader</h1>
              <p class="meta">pub4 · MASTER + RAILS · Bergen &amp; Norge<br>#{manifest_entries.size} søknader · HTU layout-1 · manifest.yml for mutt/grok<br><time datetime="#{Constants::DATE_ISO}">#{Constants::DATE}</time></p>
            </header>
            <div class="content">
              #{helpers.deadline_calendar_block(funding, limit: 6)}
              #{helpers.fun_wholesome_table(funding)}
              <h2>Spor</h2>
              <table>
                <tr><td>·</td><td><strong>innovasjon</strong> — Innovasjon Norge, SkatteFUNN, regional fond</td></tr>
                <tr><td>·</td><td><strong>helse</strong> — Mohn, Helse Vest, Gjensidige, legeforeningen</td></tr>
                <tr><td>·</td><td><strong>bolig</strong> — Startlån, vanskeligstilte, egenkapital (ærlig, separat spor)</td></tr>
                <tr><td>·</td><td><strong>prosjekt</strong> — brgen, amber, bsdports, SYRE, Ditt Parti, Ilumi m.fl.</td></tr>
              </table>
              <h2>Alle søknader</h2>
              <table>
                <tr><td>#</td><td>Giver</td><td>Spor</td><td>Frist</td></tr>
                #{rows}
              </table>
              <h2>Automatisering</h2>
              <table>
                <tr><td>·</td><td><code>ruby ../grok_send_legats.rb --list-batches</code></td></tr>
                <tr><td>·</td><td><code>ruby ../grok_send_legats.rb --batch bolig_asap --dry-run</code></td></tr>
                <tr><td>·</td><td><code>ruby ../grok_send_legats.rb --batch all_sendable</code></td></tr>
              </table>
              <p>Se også <code>manifest.yml</code>, <code>batches.yml</code>, <code>bergen_catalog.yml</code>.</p>
              <p><a href="../index.html">← Tilbake til ideer</a></p>
            </div>
            <footer>
              #{disclaimer_paragraph}
            </footer>
          </article>
          <script>
        #{TABLE_SCRIPT}
          </script>
        </body>
        </html>
      HTML
    end

    def sitemap_xml(urls)
      entries = urls.map do |loc|
        "  <url>\n    <loc>#{escape_html(loc)}</loc>\n    <lastmod>#{Constants::DATE_ISO}</lastmod>\n  </url>"
      end.join("\n")
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        #{entries}
        </urlset>
      XML
    end

    def robots_txt(base_url: Constants::BASE_URL)
      <<~TXT
        User-agent: *
        Allow: /

        Sitemap: #{base_url}/sitemap.xml
      TXT
    end
  end
end