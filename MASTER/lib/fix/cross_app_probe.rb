# frozen_string_literal: true

module Master
  module Fix
    # The geometry walk records type, radius, colour and size but not padding or
    # border. This reads those, for the same five primitives, straight from the
    # computed style of the page on screen, so a cross-app comparison can speak
    # of spacing and borders too.
    module CrossAppProbe
      JS = <<~JS
        (() => {
          const pick = (sel, n) => Array.from(document.querySelectorAll(sel))
            .filter((el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; })
            .slice(0, n);
          const insideNav = (el) => !!el.closest('nav');
          const groups = {
            header: pick('header', 1),
            nav_link: pick('nav a, nav button', 3),
            footer: pick('footer', 1),
            button: pick("button, input[type=submit], a.btn, [role=button]", 12).filter((el) => !insideNav(el)).slice(0, 3),
            form_control: pick("input:not([type=hidden]):not([type=submit]):not([type=checkbox]):not([type=radio]), select, textarea", 3),
          };
          const rows = [];
          for (const [primitive, els] of Object.entries(groups)) {
            for (const el of els) {
              const cs = getComputedStyle(el);
              const cls = (el.getAttribute('class') || '').split(/\\s+/).filter(Boolean).slice(0, 2).join('.');
              rows.push({ primitive, selector: el.tagName.toLowerCase() + (cls ? '.' + cls : ''), style: {
                height: Math.round(el.getBoundingClientRect().height * 100) / 100,
                font_size: parseFloat(cs.fontSize), font_weight: cs.fontWeight,
                line_height: cs.lineHeight === 'normal' ? null : parseFloat(cs.lineHeight),
                letter_spacing: cs.letterSpacing === 'normal' ? 0 : parseFloat(cs.letterSpacing),
                border_radius: cs.borderRadius, border_width: cs.borderTopWidth, border_color: cs.borderTopColor,
                padding: [cs.paddingTop, cs.paddingRight, cs.paddingBottom, cs.paddingLeft].join(' '),
                color: cs.color, bg: cs.backgroundColor, box_shadow: cs.boxShadow !== 'none' ? 'shadow' : 'none',
              } });
            }
          }
          return rows;
        })()
      JS

      module_function

      # Samples for the page currently on screen.
      def samples(cdp, surface)
        member = CrossAppConsistency.member(surface)
        Array(cdp.evaluate(JS)).map do |row|
          CrossAppConsistency::Sample.new(app: member, viewport: surface.viewport.to_s, primitive: row["primitive"],
                                          selector: row["selector"], style: row["style"].compact)
        end
      end
    end
  end
end
