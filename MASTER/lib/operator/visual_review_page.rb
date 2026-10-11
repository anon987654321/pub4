# frozen_string_literal: true

require "cgi"

module Operator
  # The self-contained index.html of a visual review: surfaces with thumbnails,
  # measurements and gate results, then the council's picks beside the full
  # critique text. No external asset; every image is a relative file in the
  # same folder, so the folder can be zipped and sent.
  module VisualReviewPage
    CSS = <<~CSS
      :root { --bg:#fff; --fg:#111; --mut:#5a5a5a; --line:#d8d8d8; --bad:#b00020; --ok:#0a6b2d; --card:#f6f6f6; }
      @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#111; --fg:#eee; --mut:#a0a0a0; --line:#333; --bad:#ff6b81; --ok:#5fd38d; --card:#1b1b1b; } }
      :root[data-theme="dark"] { --bg:#111; --fg:#eee; --mut:#a0a0a0; --line:#333; --bad:#ff6b81; --ok:#5fd38d; --card:#1b1b1b; }
      * { box-sizing:border-box; }
      body { margin:0; padding:16px; background:var(--bg); color:var(--fg); font:16px/1.5 "Helvetica Neue Pro","Helvetica Neue",Arial,sans-serif; }
      main { max-width:72rem; margin:0 auto; }
      h1 { font-size:1.5rem; margin:0 0 .25rem; } h2 { font-size:1.125rem; margin:2rem 0 .5rem; border-top:1px solid var(--line); padding-top:1rem; }
      code, pre, .mono { font-family:ui-monospace,Menlo,Consolas,monospace; font-size:.8125rem; }
      pre { white-space:pre-wrap; word-break:break-word; background:var(--card); padding:12px; margin:.5rem 0; overflow-x:auto; }
      .mut { color:var(--mut); } .bad { color:var(--bad); } .ok { color:var(--ok); }
      .grid { display:grid; gap:12px; grid-template-columns:repeat(auto-fill,minmax(220px,1fr)); }
      .card { background:var(--card); border:1px solid var(--line); padding:8px; min-width:0; }
      .card img { width:100%; height:auto; display:block; border:1px solid var(--line); }
      .card h3 { font-size:.875rem; margin:.5rem 0 .25rem; word-break:break-word; }
      ul { padding-left:1.25rem; margin:.25rem 0; } li { margin:.25rem 0; word-break:break-word; }
      a { color:inherit; }
    CSS

    module_function

    def h(value) = CGI.escapeHTML(value.to_s)

    def render(model)
      <<~HTML
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Visual review</title><style>#{CSS}</style></head><body><main>
        <h1>Visual review</h1>
        <p class="mut mono">#{h(model[:generated_at])} &middot; #{h(model[:summary])}</p>
        #{notes(model[:notes])}#{coverage(model)}#{sheet(model)}#{overlays(model[:overlays])}#{picks(model)}#{surfaces(model[:rows])}#{extras(model[:extras])}
        </main></body></html>
      HTML
    end

    def notes(list)
      return "" if Array(list).empty?

      "<ul>#{list.map { |n| "<li class=\"bad\">#{h(n)}</li>" }.join}</ul>"
    end

    def coverage(model)
      missed = Array(model[:missing])
      body = missed.empty? ? "<p class=\"ok\">Every declared surface was captured.</p>" :
        "<p class=\"bad\">Declared but not captured (#{missed.size}):</p><ul class=\"mono\">#{missed.map { |id| "<li>#{h(id)}</li>" }.join}</ul>"
      "<h2>Coverage</h2><p>#{h(model[:coverage_line])}</p>#{body}"
    end

    def sheet(model)
      return "" unless model[:contact_sheet]

      "<h2>Contact sheet</h2><a href=\"#{h(model[:contact_sheet])}\"><img alt=\"contact sheet\" style=\"max-width:100%;height:auto\" src=\"#{h(model[:contact_sheet])}\"></a>"
    end

    def overlays(list)
      return "" if Array(list).empty?

      cards = list.map { |o| card(o[:label], o[:path], o[:text]) }.join
      "<h2>Cross-page overlays</h2><div class=\"grid\">#{cards}</div>"
    end

    def card(title, path, text = nil)
      img = path ? "<a href=\"#{h(path)}\"><img loading=\"lazy\" alt=\"#{h(title)}\" src=\"#{h(path)}\"></a>" : ""
      "<div class=\"card\">#{img}<h3>#{h(title)}</h3>#{text ? "<div class=\"mut mono\">#{h(text)}</div>" : ""}</div>"
    end

    def picks(model)
      return "<h2>Critique</h2><p class=\"mut\">#{h(model[:critique_note])}</p>" unless model[:critique]

      items = Array(model[:picks]).map do |pick|
        place = pick[:anchored] ? "<span class=\"ok mono\">anchored #{h(pick[:file])}:#{h(pick[:line])}</span>" : "<span class=\"bad mono\">unanchored</span>"
        "<li>#{place}<br>#{h(pick[:text])}</li>"
      end
      list = items.empty? ? "<p class=\"mut\">The council made no picks.</p>" : "<ul>#{items.join}</ul>"
      "<h2>Critique picks (#{Array(model[:picks]).size})</h2>#{list}<h2>Critique text</h2><pre>#{h(model[:critique_text])}</pre>"
    end

    def surfaces(rows)
      cards = Array(rows).map { |row| surface_card(row) }.join
      "<h2>Surfaces and states (#{Array(rows).size})</h2><div class=\"grid\">#{cards}</div>"
    end

    def surface_card(row)
      bad = row[:problems].to_a
      status = bad.empty? ? "<span class=\"ok\">gates clean</span>" : "<span class=\"bad\">#{bad.size} gate problem(s)</span>"
      metrics = row[:metrics].to_h.map { |k, v| "#{h(k)}=#{h(v)}" }.join(" ")
      lines = bad.map { |line| "<li class=\"bad mono\">#{h(line)}</li>" }.join
      links = Array(row[:extras]).map { |e| "<a href=\"#{h(e[:path])}\">#{h(e[:label])}</a>" }.join(" &middot; ")
      shot = row[:screenshot]
      img = shot ? "<a href=\"#{h(shot)}\"><img loading=\"lazy\" alt=\"#{h(row[:title])}\" src=\"#{h(shot)}\"></a>" : ""
      "<div class=\"card\">#{img}<h3>#{h(row[:title])}</h3>#{status}<div class=\"mono mut\">#{metrics}</div><ul>#{lines}</ul><div class=\"mono\">#{links}</div></div>"
    end

    def extras(sections)
      Array(sections).map do |name, rows|
        "<h2>#{h(name)}</h2><ul class=\"mono\">#{Array(rows).map { |r| "<li>#{h(r)}</li>" }.join}</ul>"
      end.join
    end
  end
end
