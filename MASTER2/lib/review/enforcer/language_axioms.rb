# frozen_string_literal: true

module MASTER
  module Review
    # LanguageAxioms - Language-specific beauty rules
    # 78 axioms across Ruby, Rails, Zsh, HTML/ERB, CSS/SCSS, JavaScript, and universal
    module LanguageAxioms
      AXIOMS_FILE     = File.join(MASTER.root, "data", "detectors.yml")
      DETECTION_FILE  = File.join(MASTER.root, "data", "language_detection.yml")

      class << self
        def extension_map
          @extension_map ||= begin
            data = File.exist?(DETECTION_FILE) ? YAML.safe_load_file(DETECTION_FILE) : {}
            raw  = data["extension_map"] || {}
            raw.transform_values { |v| Array(v).map(&:to_s) }
          end
        end

        def content_indicators
          @content_indicators ||= begin
            data = File.exist?(DETECTION_FILE) ? YAML.safe_load_file(DETECTION_FILE) : {}
            data["content_indicators"] || {}
          end
        end
      end

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

        def languages_for_file(filename, content: nil)
          ext = File.extname(filename.to_s).downcase
          from_ext = extension_map[ext]
          return from_ext if from_ext

          if content
            content_indicators.each do |lang, patterns|
              patterns.each do |pat|
                begin
                  return [lang.to_s, "universal"] if content.match?(Regexp.new(pat))
                rescue RegexpError
                  next
                end
              end
            end
          end

          %w[universal]
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
