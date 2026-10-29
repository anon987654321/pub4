# frozen_string_literal: true

module Master
  module Fix
    module Improve
      # The four domains /fix elevates, each with mechanical, law-grounded
      # heuristics that measure distance from the ideal without a model call.
      # A domain returns opportunities ordered by leverage; the engine picks the
      # best per run so every pass moves a real file toward its ideal.
      module Domains
        module_function

        # Leverage is the product of how far the artifact sits from its ideal
        # and how many readers a change reaches. Runtimes stay cheap: every
        # probe below is a read plus arithmetic, no LLM, no subprocess per file.
        DOMAIN_WEIGHT = { code: 1.0, prose: 0.9, visual: 1.1, music: 0.8 }.freeze

        def scan(root:, files:)
          scoped = files.select { |path| File.file?(path) }
          implementations = {
            code: method(:scan_code), prose: method(:scan_prose),
            visual: method(:scan_visual), music: method(:scan_music)
          }
          domains = scoped.filter_map { |path| domain_for(path) }.uniq
          domains.flat_map do |domain|
            candidates = scoped.select { |path| domain_for(path) == domain }
            implementations.fetch(domain).call(root:, files: candidates.first(400))
          end.sort_by { |opportunity| -opportunity.leverage }
        end

        def domain_for(path)
          case File.extname(path).downcase
          when ".rb" then :code
          when ".md" then :prose
          when ".erb", ".scss", ".css", ".html" then :visual
          when ".mid", ".midi", ".wav", ".flac", ".sco", ".orc", ".csd" then :music
          end
        end

        # --- code: the ideal is SIMPLEST_WORKS — one concept per file, methods a
        # reader holds, no dead weight. ---
        def scan_code(root:, files:)
          files.filter_map do |path|
            lines = File.readlines(path, encoding: "UTF-8", invalid: :replace)
            method_spans = method_boundaries(lines)
            longest = method_spans.max_by { |span| span[:end] - span[:start] }
            if longest && (longest[:end] - longest[:start]) > 48
              Opportunity.new(
                domain: :code, path:, signal: "long_method",
                detail: "#{File.basename(path)}:#{longest[:name]} runs #{longest[:end] - longest[:start]} lines; the ideal is a method a reader holds in one glance",
                leverage: 9.0 * DOMAIN_WEIGHT[:code],
                fix: "Split #{longest[:name]} at its natural seams; each part keeps one responsibility and a name that says it. Preserve behavior and public interfaces."
              )
            elsif lines.size > 400
              Opportunity.new(
                domain: :code, path:, signal: "god_file",
                detail: "#{lines.size} lines carry several concepts; the ideal is one concept per file",
                leverage: 7.0 * DOMAIN_WEIGHT[:code],
                fix: "Extract the largest coherent concept into its own file with a name that states it; require it from this file so nothing else changes."
              )
            elsif lines.first.to_s.strip != "# frozen_string_literal: true" && lines.size > 12
              Opportunity.new(
                domain: :code, path:, signal: "unfrozen_literals",
                detail: "missing '# frozen_string_literal: true'; every string allocates a fresh mutable object",
                leverage: 4.0 * DOMAIN_WEIGHT[:code],
                fix: "Add '# frozen_string_literal: true' as the first line and confirm no caller mutates the file's strings in place."
              )
            end
          end
        end

        def method_boundaries(lines)
          starts = []
          lines.each_with_index do |text, index|
            match = text.match(/^\s*def\s+(?:self\.)?([A-Za-z_][A-Za-z0-9_?!=]*)/)
            starts << { name: match[1], start: index } if match
          end
          starts.each_with_index.map do |entry, index|
            finish = index + 1 < starts.size ? starts[index + 1][:start] : lines.size
            { name: entry[:name], start: entry[:start], end: finish }
          end
        end

        # --- prose: the ideal is a README a stranger can act on — a claim of
        # what this is, how to run it, and where the truth lives. ---
        def scan_prose(root:, files:)
          files.filter_map do |path|
            text = File.read(path, encoding: "UTF-8", invalid: :replace)
            words = text.split(/\s+/).size
            headings = text.scan(/^#+\s+/m).size
            if words < 60 && File.basename(path) =~ /README|CONTRIBUTING|ARCHITECTURE/i
              Opportunity.new(
                domain: :prose, path:, signal: "thin_document",
                detail: "#{words} words cannot carry what a stranger needs; the ideal names purpose, run steps and the source of truth",
                leverage: 8.0 * DOMAIN_WEIGHT[:prose],
                fix: "Write the three sections a stranger needs: what this is and for whom, how to run or install it, where the canonical laws/tests live."
              )
            elsif headings.zero? && words > 240
              Opportunity.new(
                domain: :prose, path:, signal: "wall_of_text",
                detail: "#{words} words without a single heading; readers cannot navigate what they cannot scan",
                leverage: 6.0 * DOMAIN_WEIGHT[:prose],
                fix: "Add headings that partition the text by the questions a reader arrives with; keep every claim under the heading that answers it."
              )
            elsif text.match?(/\bTBD\b|\bTODO:\s*write\b|lorem ipsum/i)
              Opportunity.new(
                domain: :prose, path:, signal: "placeholder",
                detail: "placeholder text promises content the file does not deliver",
                leverage: 7.5 * DOMAIN_WEIGHT[:prose],
                fix: "Replace the placeholder with the real content it promised, or remove the section and let the document stand on what is true."
              )
            end
          end
        end

        # --- visual: the ideal is a surface that names its tokens, keeps
        # tap targets usable, and carries no rule nothing renders. ---
        def scan_visual(root:, files:)
          files.filter_map do |path|
            text = File.read(path, encoding: "UTF-8", invalid: :replace)
            if File.extname(path) == ".erb" && text.match?(/<img\b(?![^>]*\balt=)/i)
              Opportunity.new(
                domain: :visual, path:, signal: "image_without_alt",
                detail: "an <img> renders without alt text; the ideal describes every image a reader may meet",
                leverage: 9.5 * DOMAIN_WEIGHT[:visual],
                fix: "Give the <img> an alt that states what the reader learns from it; decorative images take alt=\"\"."
              )
            elsif File.extname(path) == ".erb" && text.match?(/<a\b(?![^>]*\b(aria-label|title)=)[^>]*>\s*(<i |<span class="[^"]*icon)/im)
              Opportunity.new(
                domain: :visual, path:, signal: "icon_only_link",
                detail: "an icon-only link has no accessible name",
                leverage: 9.0 * DOMAIN_WEIGHT[:visual],
                fix: "Add an aria-label naming the link's destination; the icon is decoration, the name is the meaning."
              )
            elsif File.extname(path) == ".scss" && text.match?(/#[0-9a-fA-F]{3,6}\b/) && text.match?(/\$[a-z-]/).nil?
              Opportunity.new(
                domain: :visual, path:, signal: "raw_hex_colors",
                detail: "hard-coded hex colors bypass the token contract; the ideal resolves every color through a token",
                leverage: 5.5 * DOMAIN_WEIGHT[:visual],
                fix: "Replace raw hex colors with the design tokens they correspond to; if no token fits, add one rather than hard-code again."
              )
            end
          end
        end

        # --- music: the ideal is a part the performer can read — TEMPO named,
        # dynamics marked, structure stated. Score sources (.sco/.orc/.csd) and
        # any music metadata the tree carries. ---
        def scan_music(root:, files:)
          files.filter_map do |path|
            text = File.read(path, encoding: "UTF-8", invalid: :replace)
            if /\.(sco|orc|csd)\z/.match?(path)
              missing = []
              missing << "no tempo statement" unless text.match?(/\btempo\b|\bt\s+\d+/i)
              missing << "no dynamics marking" unless text.match?(/\bp[3-9]\b|cresc|dim|ff|pp/i)
              next if missing.empty?

              Opportunity.new(
                domain: :music, path:, signal: "unmarked_score",
                detail: missing.join("; ") + "; the ideal is a part a performer reads without asking",
                leverage: 6.0 * DOMAIN_WEIGHT[:music],
                fix: "Add the missing markings (#{missing.join(", ")}) at the top of the score; a performer should never guess tempo or dynamics."
              )
            elsif File.extname(path) == ".yml" && text.match?(/\b(bpm|tempo|instrument):\s*\z/)
              Opportunity.new(
                domain: :music, path:, signal: "empty_music_field",
                detail: "a tempo/instrument field is declared but empty",
                leverage: 4.0 * DOMAIN_WEIGHT[:music],
                fix: "Fill or remove the empty music field; declared-but-empty is worse than absent."
              )
            end
          end
        end
      end
    end
  end
end
