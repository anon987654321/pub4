# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Rules
        # Surface law: pixel/UI aesthetic + Rails HTML/JS/ERB conventions.
        # One file — views, CSS, Stimulus, touch targets, flat design.

        # Pixel-perfect UI/UX rules restored from master.yml aesthetics + design_rules.yml.
        # Applies to MASTER/web face, ERB views, and pub4/RAILS SCSS/HTML.

        UI_PATH = %r{(?:/app/views/|/app/assets/|/web/public/|/web/app/|face\.|/RAILS/)}i.freeze
        CSS_LANGS = %i[css scss].freeze
        HTML_LANGS = %i[html].freeze

        module_function

        def ui_path?(path)
          path.to_s.match?(UI_PATH) || path.to_s.include?("views") || path.to_s.end_with?(".erb", ".html", ".scss", ".css")
        end

        def thresholds
          Master::Design::Thresholds
        end

        RuleDSL.rule :NO_DECORATIVE_FX,
          severity: :warning, tags: %i[DESIGN AESTHETIC PIXEL], applies_to: CSS_LANGS, autofix: false,
          description: "flat UI — no blur, glow, or ornamental shadow" do |src, path:|
          next [] unless Rules.ui_path?(path)

          findings = []
          src.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("//", "/*", "*")
            # allow 0 shadows / none
            next if line.match?(/box-shadow\s*:\s*(none|0\s)/i)
            next if line.match?(/text-shadow\s*:\s*(none|0\s)/i)

            if line.match?(/box-shadow\s*:/i) || line.match?(/text-shadow\s*:/i)
              findings << finding(line: num, message: "ornamental shadow — flat UI: use border/contrast, not glow (design_rules pixel_perfection)")
            end
            if line.match?(/filter\s*:\s*[^;]*blur\s*\(/i) || line.match?(/backdrop-filter\s*:/i)
              findings << finding(line: num, message: "blur/backdrop-filter — forbidden decorative FX for pixel-perfect flat surfaces")
            end
          end
          findings
        end

        RuleDSL.rule :FLAT_PIXELS,
          severity: :warning, tags: %i[DESIGN AESTHETIC PIXEL], applies_to: %i[css scss javascript], autofix: false,
          description: "canvas/pixel layers stay crisp — no smoothing/glow language" do |src, path:|
          findings = []
          if path.to_s.match?(/\.(js|ts)\z/) || File.basename(path.to_s).match?(/face/)
            src.each_line.with_index(1) do |line, num|
              if line.match?(/imageSmoothingEnabled\s*=\s*true/i)
                findings << finding(line: num, message: "imageSmoothingEnabled=true — pixel field requires false (integer scale)")
              end
              if line.match?(/\b(particle|bloom|scanline|vaporwave|crt)\b/i) && !line.strip.start_with?("//", "*", "/*")
                findings << finding(line: num, message: "decorative particle/CRT language — use pixel-field/semantic cell terms per design_rules")
              end
            end
          end
          findings
        end

        RuleDSL.rule :EIGHT_PX_RHYTHM,
          severity: :info, tags: %i[DESIGN AESTHETIC], applies_to: CSS_LANGS, autofix: false,
          description: "spacing on 8px rhythm (4px hairline allowed)" do |src, path:|
          next [] unless Rules.ui_path?(path)

          allowed = Rules.thresholds.eight_px_rhythm.map(&:to_i)
          findings = []
          src.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("//", "/*", "*")
            line.scan(/(?:margin|padding|gap|top|left|right|bottom|inset)(?:-\w+)?\s*:\s*(-?\d+)px/i) do |raw|
              px = raw[0].to_i.abs
              next if allowed.include?(px) || px.zero?
              next if px % 4 == 0 && px <= 96 # 4px grid hairlines

              findings << finding(line: num, message: "#{px}px spacing off 8px rhythm — use #{allowed.select { |n| n.between?(px - 8, px + 8) }.join('/')} (design_rules)")
            end
          end
          findings.uniq { |f| [f[:line], f[:message]] }
        end

        RuleDSL.rule :TOUCH_TARGET_MIN,
          severity: :warning, tags: %i[DESIGN UX ACCESSIBILITY], applies_to: CSS_LANGS, autofix: false,
          description: "Fitts — interactive targets ≥44px" do |src, path:|
          next [] unless Rules.ui_path?(path)

          min = Rules.thresholds.touch_min_px.to_i
          findings = []
          src.each_line.with_index(1) do |line, num|
            next unless line.match?(/min-(?:width|height)|height|width/i)
            next unless line.match?(/button|\.btn|tap|touch|click|icon-btn|nav__|control/i) ||
                        (line.match?(/min-height|height/) && path.to_s.include?("button"))

            line.scan(/(?:min-)?(?:width|height)\s*:\s*(\d+)px/i) do |raw|
              px = raw[0].to_i
              next if px >= min || px.zero?

              findings << finding(line: num, message: "touch target #{px}px < #{min}px (Fitts / design_rules.ux_laws.fitts)")
            end
          end
          findings
        end

        RuleDSL.rule :CHOICE_OVERLOAD,
          severity: :info, tags: %i[DESIGN UX], applies_to: HTML_LANGS, autofix: false,
          description: "Hick — too many peer choices without grouping" do |src, path:|
          next [] unless Rules.ui_path?(path)

          max = Rules.thresholds.max_visible_choices.to_i
          findings = []
          # count sibling <li> or nav links in a single block
          src.scan(/<(?:ul|nav|select)[^>]*>(.*?)<\/(?:ul|nav|select)>/im) do |body|
            chunk = body[0].to_s
            count = chunk.scan(/<li\b/i).size
            count = chunk.scan(/<option\b/i).size if count.zero?
            count = chunk.scan(/<a\b/i).size if count.zero?
            next if count <= max

            line = src[0, src.index(chunk) || 0].count("\n") + 1
            findings << finding(line: line, message: "#{count} peer choices > #{max} (Hick) — group or progressive disclosure")
          end
          findings
        end

        RuleDSL.rule :PROGRESSIVE_DISCLOSURE,
          severity: :info, tags: %i[DESIGN UX], applies_to: HTML_LANGS, autofix: false,
          description: "advanced controls should not dump all options at once" do |src, path:|
          next [] unless path.to_s.include?("/app/views/") || path.to_s.include?("web/")
          next [] unless src.match?(/advanced|settings|options|preferences/i)
          next [] if src.match?(/details|disclosure|collapsed|hidden|aria-expanded|data-controller=["'][^"']*disclosure/i)

          [finding(line: 1, message: "settings/advanced UI without disclosure pattern — collapse secondary controls")]
        end

        RuleDSL.rule :WHITESPACE_RHYTHM,
          severity: :info, tags: %i[DESIGN AESTHETIC], applies_to: CSS_LANGS, autofix: false,
          description: "ma — breathing room via gap/section spacing tokens" do |src, path:|
          next [] unless Rules.ui_path?(path)
          next [] unless src.match?(/section|hero|card|panel|main/i)
          next [] if src.match?(/gap\s*:|section.*padding|padding-block|margin-block/i)

          [finding(line: 1, message: "layout surface without gap/section spacing — set rhythm tokens (design_rules negative_space)")]
        end

        RuleDSL.rule :TYPE_HIERARCHY,
          severity: :info, tags: %i[DESIGN TYPOGRAPHY], applies_to: CSS_LANGS, autofix: false,
          description: "modular type scale — flag one-off font sizes" do |src, path:|
          next [] unless Rules.ui_path?(path)

          sizes = src.scan(/font-size\s*:\s*([\d.]+)px/i).flatten.map(&:to_f)
          next [] if sizes.size < 5

          unique = sizes.uniq
          next [] if unique.size <= 8

          [finding(line: 1, message: "#{unique.size} distinct px font sizes — prefer modular scale ≤8 sizes (design_rules.type_scale)")]
        end

        RuleDSL.rule :CONTRAST_TOKENS,
          severity: :info, tags: %i[DESIGN ACCESSIBILITY], applies_to: CSS_LANGS, autofix: false,
          description: "prefer token colors over low-contrast gray-on-gray magic" do |src, path:|
          next [] unless Rules.ui_path?(path)

          findings = []
          src.each_line.with_index(1) do |line, num|
            next unless line.match?(/color\s*:\s*#([0-9a-f]{3,8})/i)
            hex = line[/color\s*:\s*#([0-9a-f]{3,8})/i, 1].to_s
            next if hex.empty?
            # crude: very light gray text
            if hex.match?(/\A([ef]{3}|[ef]{6}|ccc|ddd|eee)\z/i)
              findings << finding(line: num, message: "low-contrast light gray text ##{hex} — use semantic token with AAA body contrast")
            end
          end
          findings
        end

        RuleDSL.rule :PIXEL_EXACT,
          severity: :info, tags: %i[DESIGN AESTHETIC PIXEL], applies_to: CSS_LANGS, autofix: false,
          description: "avoid subpixel/fractional layout that breaks integer grids" do |src, path:|
          next [] unless Rules.ui_path?(path)

          scan_lines(src, /(?:width|height|top|left|margin|padding|transform:\s*translate)\s*:\s*[\d.]+\.\d+px/i,
            message: "fractional px — prefer integer pixels for pixel-perfect alignment")
        end

        RuleDSL.rule :FORM_FOLLOWS_FUNCTION,
          severity: :info, tags: %i[DESIGN AESTHETIC], applies_to: HTML_LANGS, autofix: false,
          description: "decorative empty wrappers without content/role" do |src, path:|
          next [] unless Rules.ui_path?(path)

          scan_lines(src, /<div\s+class=["'][^"']*(?:decor|ornament|spacer|filler|gradient-bg)[^"']*["']\s*>\s*<\/div>/i,
            message: "decorative empty div — form follows function; remove or attach semantics")
        end

        RuleDSL.rule :SIGNAL_NOISE,
          severity: :info, tags: %i[DESIGN AESTHETIC], applies_to: HTML_LANGS, autofix: false,
          description: "too many competing visual classes on one node" do |src, path:|
          next [] unless Rules.ui_path?(path)

          src.each_line.with_index(1).filter_map do |line, num|
            m = line.match(/class=["']([^"']+)["']/)
            next unless m
            classes = m[1].split(/\s+/)
            next if classes.size < 8

            finding(line: num, message: "#{classes.size} classes on one node — signal/noise; move layout to SCSS")
          end
        end

        RuleDSL.rule :AFFORDANCE_CLARITY,
          severity: :warning, tags: %i[DESIGN UX], applies_to: HTML_LANGS, autofix: false,
          description: "clickable non-buttons need clear affordance" do |src, path:|
          next [] unless Rules.ui_path?(path)

          scan_lines(src, /<(div|span)[^>]*(data-action|onclick|data-controller)[^>]*>/i,
            message: "interactive div/span — use <button> or explicit role+tabindex+keyboard handler")
        end

        RuleDSL.rule :AESTHETIC_MINIMALISM,
          severity: :info, tags: %i[DESIGN AESTHETIC], applies_to: HTML_LANGS, autofix: false,
          description: "Rams less-but-better — flag icon+label+badge pileups" do |src, path:|
          next [] unless Rules.ui_path?(path)

          scan_lines(src, /<(button|a)[^>]*>.*?<(svg|img|i)[^>]*>.*?<(span|small|badge)/im,
            message: "control packs icon+extra chrome — prefer one signal (label or icon)")
        end

        %w[USEFUL UNDERSTANDABLE UNOBTRUSIVE HONEST THOROUGH].each do |trait|
          RuleDSL.rule :"RAMS_#{trait}",
            severity: :info, tags: %i[DESIGN RAMS], applies_to: HTML_LANGS, autofix: false,
            description: "Rams checklist tag: #{trait.downcase}" do |src, path:|
            next [] unless Rules.ui_path?(path)
            next [] unless path.to_s.include?("/app/views/") || path.to_s.include?("web/")

            # Soft detectors — high-signal anti-patterns only
            case trait
            when "HONEST"
              scan_lines(src, /loading.*?100%|progress.*?100%|fake[-_ ]progress/i,
                message: "possible dishonest progress UI — state must match system (Rams honest)")
            when "THOROUGH"
              next [] unless src.match?(/<form\b/i)
              next [] if src.match?(/error|invalid|aria-invalid|field_with_errors|empty|blank/i)
              [finding(line: 1, message: "form without visible error/empty handling — Rams thorough")]
            when "UNOBTRUSIVE"
              scan_lines(src, /modal|overlay|popup|interstitial/i,
                message: "attention-capturing chrome — keep unobtrusive unless blocking is required")
            when "UNDERSTANDABLE"
              scan_lines(src, /placeholder=["'][^"']{1,3}["']/,
                message: "cryptic placeholder — labels must explain without folklore")
            when "USEFUL"
              scan_lines(src, /coming soon|lorem ipsum|placeholder content/i,
                message: "non-useful placeholder content in shipped view")
            else
              []
            end
          end
        end

        RuleDSL.rule :HOST_CAPACITY,
          severity: :warning, tags: %i[OPS], applies_to: %i[ruby], autofix: false,
          description: "carrying capacity — avoid full-repo scan/fix in hot paths" do |src, path:|
          next [] unless path.to_s.include?("lib/")

          scan_lines(src, /scan_dir\([^)]*ROOT|fix_loop\.run\(\s*(@root|root|Master::ROOT)/,
            message: "full-root scan/fix — scope to path; respect host carrying capacity")
        end

        # --- Rails app surface ---

        # Rails app law restored from master.yml rails_conventions — lexical/structural.
        # Applies under RAILS/, MASTER/web app views, and any app/ tree.

        RAILSISH = %r{(?:/RAILS/|/app/(?:controllers|models|helpers|views|javascript|assets)/)}i.freeze

        module_function

        def rails_path?(path)
          path.to_s.match?(RAILSISH)
        end

        # Line index of the matching `end` for a `def` starting at `start`,
        # via brace-depth tracking. Own method so its loop's nesting doesn't
        # compound with the caller's own while/if nesting (NESTING_DEPTH).
        def method_body_end_line(lines, start)
          depth = 0
          j = start
          while j < lines.size
            depth += lines[j].scan(/\b(do|def|class|module|if|unless|begin|case)\b/).size
            depth -= lines[j].scan(/\bend\b/).size
            j += 1
            break if depth <= 0 && j > start + 1
          end
          j
        end

        RuleDSL.rule :THIN_CONTROLLER,
          severity: :warning, tags: %i[RAILS ARCHITECTURE], applies_to: %i[ruby], autofix: false,
          description: "thin controllers — business logic belongs in models/services" do |src, path:|
          next [] unless path.to_s.include?("/controllers/")
          next [] unless path.to_s.end_with?(".rb")

          findings = []
          # fat action: many lines between def and end of public action methods
          lines = src.lines
          i = 0
          while i < lines.size
            if lines[i].match?(/^\s*def\s+\w+/)
              start = i
              j = Rules.method_body_end_line(lines, start)
              body_len = j - start
              if body_len > 40
                findings << finding(line: start + 1, message: "controller action ~#{body_len} lines — thin controllers, fat models/services (rails_conventions)")
              end
              # SQL / business in controller
              chunk = lines[start...j].join
              if chunk.match?(/\b(?:ActiveRecord::Base\.connection|find_by_sql|\.where\([^)]{40,})/m)
                findings << finding(line: start + 1, message: "query logic in controller — move to model/query object")
              end
              i = j
            else
              i += 1
            end
          end
          findings
        end

        RuleDSL.rule :FAT_MODEL_CALLBACK_SOUP,
          severity: :info, tags: %i[RAILS ARCHITECTURE], applies_to: %i[ruby], autofix: false,
          description: "limit model callback piles" do |src, path:|
          next [] unless path.to_s.include?("/models/")
          count = src.scan(/^\s*(?:before|after|around)_(?:validation|save|create|update|destroy|commit)/).size
          next [] if count <= 5
          [finding(line: 1, message: "#{count} AR callbacks — prefer services/events over callback soup")]
        end

        RuleDSL.rule :RAILS_TAG_HELPER,
          severity: :info, tags: %i[RAILS VIEWS], applies_to: %i[html], autofix: false,
          description: "prefer tag helpers over raw HTML for dynamic content" do |src, path:|
          next [] unless path.to_s.include?("/app/views/") && path.to_s.end_with?(".erb")
          findings = []
          src.each_line.with_index(1) do |line, num|
            if line.match?(/<(?:p|div|span|h[1-6])[^>]*>\s*<%=\s*(?!tag\.|content_tag|link_to|button_to|image_tag|t\(|translate)/)
              findings << finding(line: num, message: "raw HTML around <%= — prefer tag.p / content_tag per rails_conventions")
            end
          end
          findings
        end

        RuleDSL.rule :STIMULUS_CONTROLLER_SIZE,
          severity: :warning, tags: %i[RAILS JAVASCRIPT], applies_to: %i[javascript], autofix: false,
          description: "Stimulus controllers stay focused" do |src, path:|
          next [] unless path.to_s.match?(/controllers?.*\.js\z|stimulus/i) || path.to_s.include?("/javascript/")
          next [] unless src.match?(/Controller\s+extends|export default class/)
          lines = src.lines.size
          next [] if lines <= 200
          [finding(line: 1, message: "Stimulus controller #{lines} lines — split targets/actions (progressive enhancement)")]
        end

        RuleDSL.rule :STIMULUS_PROGRESSIVE,
          severity: :info, tags: %i[RAILS JAVASCRIPT UX], applies_to: %i[html], autofix: false,
          description: "interactive UI should degrade without JS when possible" do |src, path:|
          next [] unless path.to_s.include?("/app/views/")
          next [] unless src.match?(/data-controller=/)
          next [] if src.match?(/<form\b|<a\s+href=|<button\b/i)
          [finding(line: 1, message: "Stimulus island without form/link fallback — progressive enhancement")]
        end

        RuleDSL.rule :NO_LOGIC_IN_VIEW,
          severity: :warning, tags: %i[RAILS VIEWS], applies_to: %i[html], autofix: false,
          description: "views present; models/helpers compute" do |src, path:|
          next [] unless path.to_s.include?("/app/views/") && path.to_s.end_with?(".erb")
          findings = []
          src.each_line.with_index(1) do |line, num|
            next unless line.include?("<%")
            if line.match?(/<%[^=].*\b(?:each|map|select|where|find|create|update|destroy|save!)\b/)
              findings << finding(line: num, message: "business/query logic in view — move to model/helper/component")
            end
          end
          findings
        end

        RuleDSL.rule :HELPER_VIEW_ONLY,
          severity: :info, tags: %i[RAILS], applies_to: %i[ruby], autofix: false,
          description: "helpers format for views only" do |src, path:|
          next [] unless path.to_s.include?("/helpers/")
          next [] unless src.match?(/\b(?:ActiveRecord|ApplicationRecord|\.where\(|\.find\()/)
          [finding(line: 1, message: "AR access in helper — helpers format only; queries belong in models")]
        end

        RuleDSL.rule :SCSS_NESTING_DEPTH,
          severity: :warning, tags: %i[RAILS CSS DESIGN], applies_to: %i[scss], autofix: false,
          description: "avoid deep SCSS nesting / preprocessor bloat" do |src, path:|
          next [] unless Rules.rails_path?(path) || path.to_s.include?("/assets/")
          max = 0
          depth = 0
          src.each_line do |line|
            depth += line.count("{")
            depth -= line.count("}")
            depth = 0 if depth.negative?
            max = depth if depth > max
          end
          next [] if max <= 4
          [finding(line: 1, message: "SCSS nesting depth #{max} — flatten (modern CSS, no preprocessor bloat)")]
        end

        RuleDSL.rule :PWA_MANIFEST_HINT,
          severity: :info, tags: %i[RAILS PWA], applies_to: %i[json html], autofix: false,
          description: "PWA surfaces declare manifest" do |src, path:|
          next [] unless path.to_s.match?(/layout|application\.html|manifest/i)
          if path.to_s.end_with?(".erb", ".html") && src.match?(/<html/i)
            next [] if src.match?(/rel=["']manifest["']|webmanifest/i)
            [finding(line: 1, message: "layout missing web app manifest link (PWA convention)")]
          else
            []
          end
        end
      end
    end
  end
end
