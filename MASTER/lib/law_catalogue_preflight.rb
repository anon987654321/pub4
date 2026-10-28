# frozen_string_literal: true

require "pathname"
require "ripper"

module Master
  # Checks the direct Law.define population against the canonical manifest before
  # evaluating any law file. The registry audit runs after loading; this is the
  # earlier, read-only guard for failures that would otherwise prevent the audit.
  module LawCataloguePreflight
    module_function

    def validate!(law_dir:, catalogue:, repo_root:, generated_declarations: [])
      law_root = File.expand_path(law_dir)
      repository_root = File.expand_path(repo_root)
      entries = catalogue.fetch("entries")
      raise ArgumentError, "law_catalogue.entries must be a mapping" unless entries.is_a?(Hash)

      declarations = source_declarations(law_root, repository_root)
      declarations.concat(normalize_generated(generated_declarations))
      detector_declarations = source_detector_declarations(File.join(law_root, "detectors"), repository_root)
      errors = catalogue_shape_errors(catalogue, entries, law_root:, repository_root:)

      declarations.group_by { |row| row[:id] }.each do |id, rows|
        next if rows.size < 2

        locations = rows.map { |row| "#{row[:source]}:#{row[:line]}" }
        errors << "duplicate definition: #{id} at #{locations.join(', ')}"
      end

      detector_declarations.group_by { |row| row[:id] }.each do |id, rows|
        next if rows.size < 2

        locations = rows.map { |row| row[:source] }
        errors << "duplicate detector identity: #{id} in #{locations.join(', ')}"
      end

      declarations.each do |declaration|
        id = declaration.fetch(:id)
        entry = entries[id]
        if entry.nil?
          folded = entries.keys.find { |key| key.to_s.casecmp?(id) }
          if folded
            errors << "catalogue key #{folded} has the wrong case for #{id} (#{declaration[:source]}:#{declaration[:line]})"
          else
            errors << "missing catalogue entry for #{id} (#{declaration[:source]}:#{declaration[:line]})"
          end
          next
        end
        unless entry.is_a?(Hash)
          errors << "catalogue entry #{id} must be a mapping"
          next
        end

        sources = Array(entry["definition_sources"]).map(&:to_s)
        next if sources.include?(declaration.fetch(:source))

        detail = sources.empty? ? "definition_sources is empty" : "definition_sources is #{sources.join(', ')}"
        errors << "#{id} declares at #{declaration[:source]} but #{detail}"
      end

      by_source = declarations.group_by { |row| row.fetch(:source) }
      entries.each do |id, entry|
        next unless entry.is_a?(Hash)

        Array(entry["definition_sources"]).map(&:to_s).each do |source|
          next unless source.start_with?("MASTER/law/")

          resolved = File.expand_path(source, repository_root)
          next unless resolved == law_root || resolved.start_with?(law_root + File::SEPARATOR)

          unless File.file?(resolved)
            errors << "#{id} definition source does not exist: #{source}"
            next
          end

          unless File.dirname(resolved) == law_root
            errors << "#{id} definition source is outside Law.load_all's direct-file scope: #{source}"
            next
          end

          declared_ids = Array(by_source[source]).map { |row| row.fetch(:id) }
          errors << "#{id} names #{source}, but that source does not define #{id}" unless declared_ids.include?(id.to_s)
        end

        Array(entry["detector_sources"]).map(&:to_s).each do |source|
          next unless source.start_with?("MASTER/law/detectors/")

          resolved = File.expand_path(source, repository_root)
          expected_root = File.expand_path(File.join(law_root, "detectors"))
          unless resolved.start_with?(expected_root + File::SEPARATOR) && File.file?(resolved)
            errors << "#{id} detector source does not exist inside the detector directory: #{source}"
            next
          end

          declared_ids = detector_declarations.select { |row| row.fetch(:source) == source }.map { |row| row.fetch(:id) }
          errors << "#{id} names #{source}, but that source does not declare detector #{id}" unless declared_ids.include?(id.to_s)
        end
      end

      detector_declarations.each do |declaration|
        id = declaration.fetch(:id)
        entry = entries[id]
        unless entry.is_a?(Hash)
          errors << "detector #{id} in #{declaration[:source]} has no catalogue entry"
          next
        end

        sources = Array(entry["detector_sources"]).map(&:to_s)
        errors << "detector #{id} in #{declaration[:source]} is not listed in detector_sources" unless sources.include?(declaration.fetch(:source))
      end

      raise ArgumentError, "Law catalogue preflight failed:\n- #{errors.uniq.join("\n- ")}" unless errors.empty?

      true
    end

    # Validate every row before Law::Builder can fail on the first bad one.
    # ConfigurationGuard protects writes; this runtime preflight also protects
    # startup from an already-broken file and reports all catalogue-shape errors.
    def catalogue_shape_errors(catalogue, entries, law_root:, repository_root:)
      errors = []
      expected_modalities = Master::LawVocabulary::MODALITIES
      modalities = Array(catalogue["modalities"]).map(&:to_s).sort
      errors << "law_catalogue.modalities must be #{expected_modalities.join(', ')}" unless modalities == expected_modalities

      surfaces = catalogue["surfaces"]
      unless surfaces.is_a?(Array) && surfaces.any? && surfaces.all? { |surface| surface.is_a?(String) && !surface.empty? }
        errors << "law_catalogue.surfaces must be a non-empty list of names"
        surfaces = []
      end
      errors << "law_catalogue.surfaces contains duplicate names" unless surfaces.uniq == surfaces

      defaults = catalogue["defaults"]
      unless defaults.is_a?(Hash)
        errors << "law_catalogue.defaults must be a mapping"
        defaults = {}
      end

      duplicate_keys = entries.keys.group_by { |id| id.to_s.downcase }.select { |_key, ids| ids.size > 1 }
      duplicate_keys.each_key { |key| errors << "duplicate case-insensitive catalogue identity: #{key}" }

      allowed_lifecycles = %w[proposed proven active observed trusted advisory retired]
      allowed_autofix = %w[never review automatic]
      allowed_modes = %w[violation opportunity]
      allowed_languages = Master::FILE_LANGUAGE_MAP.values.uniq

      entries.each do |id, row|
        name = id.to_s
        unless name.match?(/\\A[A-Za-z][A-Za-z0-9_]*\\z/)
          errors << "invalid Law catalogue identity #{name.inspect}"
        end
        unless row.is_a?(Hash)
          errors << "catalogue entry #{name} must be a mapping"
          next
        end

        errors << "Law #{name} must be universal" unless row["universal"] == true
        row_modalities = Array(row["modalities"]).map(&:to_s).sort
        errors << "Law #{name} modalities must be #{expected_modalities.join(', ')}" unless row_modalities == expected_modalities

        severity = row["severity"] || defaults["severity"]
        errors << "Law #{name} has no severity in laws.yml law_catalogue" if severity.to_s.strip.empty?

        mode = (row["mode"] || defaults["mode"]).to_s
        errors << "Law #{name} has invalid mode #{mode.inspect}" unless allowed_modes.include?(mode) unless mode.empty?

        lifecycle = (row["lifecycle"] || defaults["lifecycle"]).to_s
        errors << "Law #{name} has invalid lifecycle #{lifecycle.inspect}" unless allowed_lifecycles.include?(lifecycle)

        autofix = (row["autofix"] || defaults["autofix"]).to_s
        errors << "Law #{name} has invalid autofix policy #{autofix.inspect}" unless allowed_autofix.include?(autofix)

        if row.key?("languages")
          languages = row["languages"]
          unless languages.is_a?(Array) && languages.all? { |language| allowed_languages.include?(language.to_s) }
            errors << "Law #{name} has invalid languages"
          end
        end

        if row.key?("surfaces")
          scoped_surfaces = row["surfaces"]
          unless scoped_surfaces.is_a?(Array) && (scoped_surfaces.map(&:to_s) - surfaces).empty?
            errors << "Law #{name} has unknown assessment surfaces"
          end
        end

        { "path_pattern" => row["path_pattern"], "path" => row["path"] }.each do |field, pattern|
          next if pattern.nil? || pattern.to_s.empty?

          Regexp.new(pattern.to_s)
        rescue RegexpError => error
          errors << "Law #{name} has invalid #{field}: #{error.message}"
        end
        Array(row["path_exclude"]).each do |pattern|
          Regexp.new(pattern.to_s)
        rescue RegexpError => error
          errors << "Law #{name} has invalid path_exclude: #{error.message}"
        end

        definition_sources = row["definition_sources"]
        detector_sources = row["detector_sources"]
        [ ["definition_sources", definition_sources, %r{\\AMASTER/law/[^/]+\\.rb\\z}],
          ["detector_sources", detector_sources, %r{\\AMASTER/law/detectors/[^/]+\\.rb\\z}] ].each do |field, value, pattern|
          next if value.nil? && field == "definition_sources" && !detector_sources.nil?
          next if value.nil? && field == "detector_sources" && !definition_sources.nil?

          unless value.is_a?(Array) && value.all? { |source| source.is_a?(String) && source.match?(pattern) && !source.split("/").include?("..") }
            errors << "Law #{name} #{field} must be a list of safe in-tree Ruby paths"
          end
        end

        sources = Array(definition_sources) + Array(detector_sources)
        errors << "Law #{name} must name a definition_sources or detector_sources entry" if sources.empty?
      end

      errors
    end

    def source_declarations(law_root, repository_root)
      Dir.glob(File.join(law_root, "*.rb")).sort.flat_map do |path|
        source = Pathname.new(path).relative_path_from(Pathname.new(repository_root)).to_s.tr("\\", "/")
        body = File.read(path, encoding: "UTF-8")
        syntax = Ripper.sexp(body)
        raise ArgumentError, "Law catalogue preflight cannot parse #{source}" unless syntax

        declarations = []
        walk(syntax) do |node|
          declaration = declaration_from(node, source)
          declarations << declaration if declaration
        end
        declarations
      end
    end

    def source_detector_declarations(detector_dir, repository_root)
      Dir.glob(File.join(detector_dir, "*.rb")).sort.flat_map do |path|
        source = Pathname.new(path).relative_path_from(Pathname.new(repository_root)).to_s.tr("\\", "/")
        body = File.read(path, encoding: "UTF-8")
        ids = body.scan(/LawDSL\.law\s*\(?\s*:([A-Za-z0-9_]+)/).flatten
        ids.concat(body.scan(/declare\s+id:\s*["']([^"']+)["']/).flatten)

        # One detector family derives five catalogue identities from the traits
        # declared in its %w list. Expand that finite list; do not treat the
        # shared template name as an identity or leave those IDs unmeasured.
        body.scan(/LawDSL\.law\s+:"([^"]*#\{([A-Za-z_]\w*)\}[^"]*)"/).each do |template, variable|
          enum = body.scan(/%w\[([^\]]+)\]\.each\s+do\s+\|#{Regexp.escape(variable)}\|/).flatten
          ids.concat(enum.flat_map do |values|
            values.split.map { |value| template.gsub("#\{#{variable}\}", value) }
          end)
        end

        ids.map { |id| { id: id.to_s, source: } }
      end
    end

    def normalize_generated(rows)
      Array(rows).map do |row|
        { id: row.fetch(:id).to_s, source: row.fetch(:source).to_s, line: row[:line] || 1 }
      end
    end

    def walk(node, &block)
      return unless node.is_a?(Array)

      yield node
      node.each { |child| walk(child, &block) if child.is_a?(Array) }
    end

    def declaration_from(node, source)
      return unless node[0] == :method_add_arg

      call = node[1]
      return unless call.is_a?(Array) && call[0] == :call

      receiver = call[1]
      method = call[3]
      return unless receiver.is_a?(Array) && receiver[0] == :var_ref &&
                    receiver[1].is_a?(Array) && receiver[1][0] == :@const && receiver[1][1] == "Law"
      return unless method.is_a?(Array) && method[0] == :@ident && method[1] == "define"

      symbol = first_node(node[2]) { |candidate| candidate[0] == :symbol_literal }
      token = symbol && symbol.dig(1, 1)
      return unless token.is_a?(Array) && %i[@const @ident].include?(token[0])

      id = token[1]
      return unless id.match?(/\A[A-Z][A-Z0-9_]*\z/)

      { id:, source:, line: method.dig(2, 0) }
    end

    def first_node(node, &predicate)
      return unless node.is_a?(Array)
      return node if predicate.call(node)

      node.each do |child|
        next unless child.is_a?(Array)

        found = first_node(child, &predicate)
        return found if found
      end
      nil
    end
  end
end
