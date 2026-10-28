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
      errors = []
      validate_manifest!(catalogue, entries, errors)

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
          unless source.start_with?("MASTER/law/") && !source.split("/").include?("..")
            errors << "#{id} has invalid definition source path: #{source}"
            next
          end

          resolved = File.expand_path(source, repository_root)
          unless resolved == law_root || resolved.start_with?(law_root + File::SEPARATOR)
            errors << "#{id} definition source escapes the direct Law directory: #{source}"
            next
          end

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
          unless source.start_with?("MASTER/law/detectors/") && !source.split("/").include?("..")
            errors << "#{id} has invalid detector source path: #{source}"
            next
          end

          resolved = File.expand_path(source, repository_root)
          expected_root = File.expand_path(File.join(law_root, "detectors"))
          unless resolved.start_with?(expected_root + File::SEPARATOR) && File.dirname(resolved) == expected_root && File.file?(resolved)
            errors << "#{id} detector source does not exist directly inside the detector directory: #{source}"
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

    def validate_manifest!(catalogue, entries, errors)
      allowed_manifest_fields = %w[schema identity_source universal_by_default modalities surfaces missing_assessor defaults entries]
      unknown_manifest_fields = catalogue.keys.map(&:to_s) - allowed_manifest_fields
      errors << "law_catalogue has unknown field(s): #{unknown_manifest_fields.sort.join(', ')}" unless unknown_manifest_fields.empty?
      errors << "law_catalogue.schema must be 1" unless catalogue["schema"] == 1
      errors << "law_catalogue.identity_source must be this_section" unless catalogue["identity_source"] == "this_section"
      errors << "law_catalogue.universal_by_default must be true" unless catalogue["universal_by_default"] == true
      errors << "law_catalogue.missing_assessor must be inconclusive" unless catalogue["missing_assessor"] == "inconclusive"

      allowed_entry_fields = %w[
        universal modalities definition_sources detector_sources severity mode lifecycle autofix
        languages surfaces path path_pattern path_exclude
      ]
      expected_modalities = Master::LawVocabulary::MODALITIES.map(&:to_s).sort
      declared_modalities = Array(catalogue["modalities"]).map(&:to_s).uniq.sort
      errors << "law_catalogue.modalities must be #{expected_modalities.join(', ')}" unless declared_modalities == expected_modalities

      surfaces = catalogue["surfaces"]
      unless surfaces.is_a?(Array) && !surfaces.empty? && surfaces.all? { |surface| !surface.to_s.strip.empty? } &&
             surfaces.map(&:to_s).uniq.size == surfaces.size
        errors << "law_catalogue.surfaces must be a non-empty, unique list of named surfaces"
      end

      defaults = catalogue.fetch("defaults", {})
      defaults_valid = defaults.is_a?(Hash)
      errors << "law_catalogue.defaults must be a mapping" unless defaults_valid
      defaults = {} unless defaults_valid

      allowed_severities = %w[info warn warning error critical veto]
      allowed_modes = %w[violation opportunity]
      allowed_lifecycles = %w[proposed proven active observed trusted advisory retired]
      allowed_autofix = %w[never review automatic]
      allowed_languages = Master::FILE_LANGUAGE_MAP.values.uniq
      default_severity = defaults["severity"]
      if !default_severity.nil? && !allowed_severities.include?(default_severity.to_s)
        errors << "law_catalogue.defaults has invalid severity #{default_severity.inspect}"
      end
      default_mode = defaults["mode"]
      if !default_mode.nil? && !allowed_modes.include?(default_mode.to_s)
        errors << "law_catalogue.defaults has invalid mode #{default_mode.inspect}"
      end
      default_lifecycle = defaults["lifecycle"]
      if !default_lifecycle.nil? && !allowed_lifecycles.include?(default_lifecycle.to_s)
        errors << "law_catalogue.defaults has invalid lifecycle #{default_lifecycle.inspect}"
      end
      default_autofix = defaults["autofix"]
      if !default_autofix.nil? && !allowed_autofix.include?(default_autofix.to_s)
        errors << "law_catalogue.defaults has invalid autofix policy #{default_autofix.inspect}"
      end
      default_languages = defaults["languages"]
      unless default_languages.nil? || (default_languages.is_a?(Array) &&
        default_languages.all? { |language| allowed_languages.include?(language.to_s) })
        errors << "law_catalogue.defaults has invalid languages"
      end

      normalized_ids = entries.keys.map(&:to_s)
      invalid_ids = normalized_ids.reject { |id| id.match?(/\A[A-Za-z][A-Za-z0-9_]*\z/) }
      errors << "invalid Law catalogue identity(ies): #{invalid_ids.uniq.join(', ')}" unless invalid_ids.empty?
      duplicate_ids = normalized_ids.group_by(&:downcase).select { |_id, keys| keys.uniq.size > 1 }.keys
      errors << "case-insensitive duplicate Law identities: #{duplicate_ids.join(', ')}" unless duplicate_ids.empty?

      entries.each do |id, entry|
        unless entry.is_a?(Hash)
          errors << "catalogue entry #{id} must be a mapping"
          next
        end

        unknown_entry_fields = entry.keys.map(&:to_s) - allowed_entry_fields
        errors << "Law #{id} has unknown catalogue field(s): #{unknown_entry_fields.sort.join(', ')}" unless unknown_entry_fields.empty?
        errors << "Law #{id} must be marked universal" unless entry["universal"] == true
        modalities = Array(entry["modalities"]).map(&:to_s).uniq.sort
        errors << "Law #{id} modalities must be #{expected_modalities.join(', ')}" unless modalities == expected_modalities
        policy = defaults.merge(entry)
        severity = policy["severity"].to_s.strip
        if severity.empty?
          errors << "Law #{id} has no effective severity"
        elsif !allowed_severities.include?(severity)
          errors << "Law #{id} has invalid severity #{severity.inspect}"
        end
        mode = policy["mode"].to_s
        errors << "Law #{id} has invalid mode #{mode.inspect}" unless allowed_modes.include?(mode)
        lifecycle = policy["lifecycle"].to_s
        errors << "Law #{id} has invalid lifecycle #{lifecycle.inspect}" unless allowed_lifecycles.include?(lifecycle)
        autofix = policy["autofix"].to_s
        errors << "Law #{id} has invalid autofix policy #{autofix.inspect}" unless allowed_autofix.include?(autofix)

        if entry.key?("languages")
          languages = entry["languages"]
          unless languages.is_a?(Array) && languages.all? { |language| allowed_languages.include?(language.to_s) }
            errors << "Law #{id} has invalid languages"
          end
        end
        surfaces = catalogue["surfaces"]
        if entry.key?("surfaces")
          scoped_surfaces = entry["surfaces"]
          unless scoped_surfaces.is_a?(Array) && (scoped_surfaces.map(&:to_s) - Array(surfaces).map(&:to_s)).empty?
            errors << "Law #{id} has unknown assessment surfaces"
          end
        end

        pattern = entry["path_pattern"]
        unless pattern.nil? || pattern.to_s.empty?
          begin
            Regexp.new(pattern.to_s)
          rescue RegexpError => error
            errors << "Law #{id} has invalid path_pattern: #{error.message}"
          end
        end
        Array(entry["path_exclude"]).each do |excluded_pattern|
          begin
            Regexp.new(excluded_pattern.to_s)
          rescue RegexpError => error
            errors << "Law #{id} has invalid path_exclude: #{error.message}"
          end
        end

        %w[definition_sources detector_sources].each do |field|
          next unless entry.key?(field)
          unless entry[field].is_a?(Array) && entry[field].all? { |source| source.is_a?(String) && !source.strip.empty? }
            errors << "Law #{id} #{field} must be a list of non-empty paths"
          end
        end

        definition_sources = Array(entry["definition_sources"]).map(&:to_s)
        detector_sources = Array(entry["detector_sources"]).map(&:to_s)
        if (definition_sources + detector_sources).empty?
          errors << "Law #{id} has no definition_sources or detector_sources"
        end
      end
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
            values.split.map { |value| template.gsub("\#{#{variable}}", value) }
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
