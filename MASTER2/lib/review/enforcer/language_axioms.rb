# frozen_string_literal: true

module MASTER
  module Review
    # LanguageAxioms - Language-specific beauty rules
    # 78 axioms across Ruby, Rails, Zsh, HTML/ERB, CSS/SCSS, JavaScript, and universal
    module LanguageAxioms
      AXIOMS_FILE = File.join(MASTER.root, "data", "language_axioms.yml")

      EXTENSION_MAP = {
        ".rb"    => %w[ruby rails universal],
        ".rake"  => %w[ruby rails universal],
        ".gemspec" => %w[ruby universal],
        ".sh"    => %w[zsh universal],
        ".zsh"   => %w[zsh universal],
        ".bash"  => %w[zsh universal],
        ".html"  => %w[html_erb universal],
        ".erb"   => %w[html_erb universal],
        ".htm"   => %w[html_erb universal],
        ".css"   => %w[css_scss universal],
        ".scss"  => %w[css_scss universal],
        ".sass"  => %w[css_scss universal],
        ".js"    => %w[javascript universal],
        ".mjs"   => %w[javascript universal],
        ".jsx"   => %w[javascript universal],
        ".ts"    => %w[javascript universal],
        ".tsx"   => %w[javascript universal],
      }.freeze

      class << self
        def axioms_data
          @axioms_data ||= File.exist?(AXIOMS_FILE) ? YAML.safe_load_file(AXIOMS_FILE, symbolize_names: true) : {}
        end

        def all_axioms
          axioms_data.flat_map { |lang, rules| (rules || []).map { |r| r.merge(language: lang) } }
        end

        def axioms_for(language)
          axioms_data[language.to_sym] || []
        end

        def languages_for_file(filename)
          ext = File.extname(filename).downcase
          EXTENSION_MAP[ext] || %w[universal]
        end

        def check(code, filename: "code")
          violations = []
          languages = languages_for_file(filename)

          languages.each do |lang|
            axioms_for(lang).each do |axiom|
              pattern_str = axiom[:detect]
              next if pattern_str.nil? # Advisory-only axioms

              begin
                pattern = Regexp.new(pattern_str, Regexp::MULTILINE)
              rescue RegexpError
                next
              end

              next unless code.match?(pattern)

              violations << {
                layer: :language_axiom,
                language: lang,
                axiom_id: axiom[:id],
                axiom_name: axiom[:name],
                message: axiom[:suggest],
                severity: axiom[:severity]&.to_sym || :info,
                autofix: axiom[:autofix] || false,
                file: filename,
              }
            end
          end

          violations
        end

        def summary
          counts = {}
          axioms_data.each { |lang, rules| counts[lang] = (rules || []).size }
          counts[:total] = counts.values.sum
          counts
        end
      end
    end
  end
end
