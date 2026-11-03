# frozen_string_literal: true

require "yaml"
# TOO_BROAD_SACRED_PATHS reads Master::Soul at load time; this file is also
# required below the boot floor (write_guard -> mechanical_autofix), where soul
# is not loaded yet.
require_relative "soul"
require_relative "law_vocabulary"
require_relative "provider_catalogue_guard"
require_relative "model_catalogue_guard"
require_relative "config_sections_guard"
require_relative "review/baymard_law"

module Master
  # Validates the governing YAML by its invariants. Who may write it is a
  # separate question soul.yml's sacred_paths answer: no automated writer may,
  # and a person commits it with ordinary git. These invariants judge every
  # candidate either way, so a write that is let through is still a valid one.
  module ConfigurationGuard
    module_function

    LAW_MODALITIES = LawVocabulary::MODALITIES

    REQUIRED_RUNTIME_CONFIG_SECTIONS = %w[
      veto_pattern_config law_map transformation_policy
    ].freeze
    # The Soul manifest owns the protected-path boundary. Broad data/ or
    # retired scanner paths would freeze runtime-written configuration or code
    # that must evolve, so the shared Soul validator refuses those entries.
    TOO_BROAD_SACRED_PATHS = Master::Soul::FORBIDDEN_SACRED_PATHS
    LIVE_SOUL = File.expand_path("../data/soul.yml", __dir__)
    REQUIRED_TOKEN_MAPS = %w[
      visual_identity viewport shared_chrome system storefront_art radio luxury promotional_art
      face_root face_interface brgen_old_dark brgen_old_light openbsd_wscons social light
      vertical_accents scale layout_rules kinetic_depth visual_design motion_and_sound
      data_visualization automated_css_analysis ux_laws typography worn_type pixel_perfection
      rams_checklist ui_polish pwa ultraminimalism ad_visual_contract
    ].freeze
    TOKEN_ROOT_FIELDS = %w[tokens].freeze
    def validate(path:, content:, root: nil)
      absolute = File.expand_path(path.to_s, root || Dir.pwd)
      kind = kind_for(absolute)
      return unless kind

      if kind == :dynamic_tools
        Master::Io::DynamicTools.validate_source(content, path: absolute)
        return
      end

      data = YAML.safe_load(content, aliases: true)
      raise ArgumentError, "top-level YAML value must be a mapping" unless data.is_a?(Hash)

      case kind
      when :laws then validate_laws(data, path: absolute, text: content)
      when :law_runtime then validate_runtime_config(data, path: absolute)
      when :soul then validate_soul(data, path: absolute)
      when :providers then ProviderCatalogueGuard.validate(data)
      when :models then ModelCatalogueGuard.validate(data, path: absolute)
      when :tokens then validate_tokens(data)
      when :config_sections then ConfigSectionsGuard.validate(data, path: absolute)
      when :baymard_ux then Review::BaymardLaw.validate_profile!(data, root: File.dirname(File.dirname(absolute)))
      end
      nil
    rescue Psych::Exception, ArgumentError, KeyError, TypeError => e
      "configuration invariant failed: #{e.class}: #{e.message}"
    rescue StandardError => e
      "configuration invariant failed: #{e.class}: #{e.message}"
    end

    def kind_for(path)
      normalized = File.expand_path(path.to_s).tr("\\", "/")
      return :laws if normalized.match?(%r{/MASTER/data/laws\.yml\z})
      return :law_runtime if normalized.match?(%r{/MASTER/data/law_runtime\.yml\z})
      return :soul if normalized.match?(%r{/MASTER/data/soul\.yml\z})
      return :baymard_ux if normalized.match?(%r{/MASTER/data/baymard_ux\.yml\z})
      return :providers if normalized.match?(%r{/MASTER/data/providers\.yml\z})
      return :models if normalized.match?(%r{/MASTER/data/models\.yml\z})
      return :tokens if normalized.match?(%r{/MASTER/data/tokens\.yml\z})
      return :dynamic_tools if normalized.match?(%r{/MASTER/data/tools\.dynamic\.yml\z})
      return :config_sections if normalized.match?(%r{/MASTER/data/(?:console|scan|budgets)\.yml\z})

      nil
    end

    def validate_tokens(document)
      unknown = document.keys.map(&:to_s) - TOKEN_ROOT_FIELDS
      errors = []
      errors << "tokens.yml has unknown top-level field(s): #{unknown.sort.join(', ')}" unless unknown.empty?

      tokens = document["tokens"]
      unless tokens.is_a?(Hash) && !tokens.empty?
        raise ArgumentError, "tokens.yml must contain a non-empty tokens mapping"
      end

      missing = REQUIRED_TOKEN_MAPS - tokens.keys.map(&:to_s)
      errors << "tokens.yml is missing required token section(s): #{missing.join(', ')}" unless missing.empty?

      tokens.each do |name, value|
        if name.to_s == "vertical_accent_ink"
          errors << "tokens.vertical_accent_ink must be non-empty text" unless value.is_a?(String) && !value.strip.empty?
        elsif !value.is_a?(Hash)
          errors << "tokens.#{name} must be a mapping"
        end
      end

      identity = tokens["visual_identity"].is_a?(Hash) ? tokens["visual_identity"] : {}
      %w[name signal signal_ink signal_on_light display_size].each do |field|
        errors << "tokens.visual_identity.#{field} must be non-empty text" unless
          identity[field].is_a?(String) && !identity[field].strip.empty?
      end

      chrome = tokens["shared_chrome"].is_a?(Hash) ? tokens["shared_chrome"] : {}
      %w[font font_code transition_fast transition_normal chrome_inset].each do |field|
        errors << "tokens.shared_chrome.#{field} must be non-empty text" unless
          chrome[field].is_a?(String) && !chrome[field].strip.empty?
      end

      social = tokens["social"].is_a?(Hash) ? tokens["social"] : {}
      %w[bg surface surface_elevated search_bg text text_secondary border accent danger
         radius_extra_small radius_small radius_medium radius_card radius_large radius_pill].each do |field|
        errors << "tokens.social.#{field} must be non-empty text" unless
          social[field].is_a?(String) && !social[field].strip.empty?
      end

      face_root = tokens["face_root"].is_a?(Hash) ? tokens["face_root"] : {}
      %w[anchors derived layout palette].each do |field|
        errors << "tokens.face_root.#{field} must be a mapping" unless face_root[field].is_a?(Hash)
      end
      %w[font_mono font_label face_bg].each do |field|
        errors << "tokens.face_root.#{field} must be non-empty text" unless
          face_root[field].is_a?(String) && !face_root[field].strip.empty?
      end

      interface = tokens["face_interface"].is_a?(Hash) ? tokens["face_interface"] : {}
      errors << "tokens.face_interface.schema must be 1" unless interface["schema"] == 1
      prompt = interface["prompt"].is_a?(Hash) ? interface["prompt"] : {}
      state = interface["state"].is_a?(Hash) ? interface["state"] : {}
      stipple = interface["stipple"].is_a?(Hash) ? interface["stipple"] : {}
      %w[font measure_ch max_ch line_height user_token master_token].each do |field|
        errors << "tokens.face_interface.prompt.#{field} is required" unless prompt.key?(field)
      end
      modes = state["modes"]
      unless modes.is_a?(Array) && !modes.empty? &&
             modes.all? { |mode| mode.is_a?(String) && !mode.strip.empty? } && modes.uniq == modes
        errors << "tokens.face_interface.state.modes must be a unique non-empty list of names"
        modes = []
      end
      errors << "tokens.face_interface.state.default_mode must be listed in modes" unless modes.include?(state["default_mode"])
      profiles = stipple["profiles"]
      unless profiles.is_a?(Hash) && (modes - profiles.keys.map(&:to_s)).empty?
        errors << "tokens.face_interface.stipple.profiles must define every face mode"
      end

      scale = tokens["scale"].is_a?(Hash) ? tokens["scale"] : {}
      spacing = scale["space_px"]
      unless spacing.is_a?(Array) && !spacing.empty? &&
             spacing.all? { |value| value.is_a?(Numeric) && value >= 0 } && spacing.uniq == spacing
        errors << "tokens.scale.space_px must be a unique list of non-negative numbers"
      end
      grid_spacing = tokens.dig("layout_rules", "grid", "allowed_spacing_px") if tokens["layout_rules"].is_a?(Hash)
      rhythm = tokens.dig("pixel_perfection", "eight_px_rhythm") if tokens["pixel_perfection"].is_a?(Hash)
      errors << "tokens.scale.space_px must match layout_rules.grid.allowed_spacing_px" unless spacing == grid_spacing
      errors << "tokens.scale.space_px must match pixel_perfection.eight_px_rhythm" unless spacing == rhythm

      touch = tokens.dig("layout_rules", "touch", "target_min_px")
      fitts = tokens.dig("ux_laws", "fitts", "target_min_px")
      errors << "tokens.layout_rules.touch.target_min_px must match ux_laws.fitts.target_min_px" unless
        touch.is_a?(Numeric) && touch == fitts

      ad = tokens["ad_visual_contract"].is_a?(Hash) ? tokens["ad_visual_contract"] : {}
      errors << "tokens.ad_visual_contract.version must be 1" unless ad["version"] == 1
      %w[colors typography spacing radius placement render].each do |field|
        value = ad[field]
        errors << "tokens.ad_visual_contract.#{field} must be a mapping" unless value.is_a?(Hash)
      end
      pairs = ad["contrast_pairs"]
      errors << "tokens.ad_visual_contract.contrast_pairs must be a non-empty list" unless pairs.is_a?(Array) && !pairs.empty?

      raise ArgumentError, errors.uniq.join("; ") unless errors.empty?
      true
    end

    def validate_soul(data, path: LIVE_SOUL)
      raise ArgumentError, "soul schema must be 1" unless data["schema"] == 1
      raise ArgumentError, "soul version must match MASTER::Soul::VERSION" unless data["version"] == Master::Soul::VERSION

      expected_digest = Master::Soul.print.fetch("body_sha256")
      unless data["body_sha256"].to_s == expected_digest
        raise ArgumentError, "soul body_sha256 must match MASTER/lib/soul.rb (#{expected_digest})"
      end

      raise ArgumentError, "soul constitution must be MASTER/data/laws.yml" unless
        data["constitution"] == "MASTER/data/laws.yml"

      Master::Soul.validate_authority_order!(data["authority_order"])
      absolute = data.fetch("absolute") { raise KeyError, "absolute.sacred_paths is required" }
      raise ArgumentError, "absolute must be a mapping" unless absolute.is_a?(Hash)
      unknown_absolute = absolute.keys.map(&:to_s) - %w[sacred_paths anti_simulation]
      raise ArgumentError, "absolute has unknown field(s): #{unknown_absolute.join(', ')}" unless unknown_absolute.empty?
      Master::Soul.validate_sacred_paths!(absolute["sacred_paths"])
      Master::Soul.validate_anti_simulation!(absolute["anti_simulation"])

      references = data.fetch("references") { raise KeyError, "references.golden_law is required" }
      raise ArgumentError, "references must be a mapping" unless references.is_a?(Hash)
      raise ArgumentError, "references may only identify laws, not define them" unless
        references.keys.map(&:to_s) == ["golden_law"]

      master_root = File.dirname(File.dirname(path))
      laws_root = File.file?(File.join(master_root, "data", "laws.yml")) ? master_root : Master::ROOT
      laws = Master.laws_document(root: laws_root)
      golden_id = references["golden_law"].to_s
      golden = laws[golden_id]
      unless golden.is_a?(Hash) && golden["statement"].to_s.match?(/preserve/i)
        raise ArgumentError, "references.golden_law must resolve to an existing preservation Law in laws.yml"
      end

      forbidden = %w[precedence precedence_graph priority severity severity_rank
                     severity_vocabulary roots_vocabulary sacred_paths protected_paths
                     enforcement law_catalogue law_map]
      shadowed = forbidden.select { |key| data.key?(key) }
      raise ArgumentError, "soul.yml cannot shadow law-owned field(s): #{shadowed.join(', ')}" unless shadowed.empty?

      temperament = data.fetch("temperament") { raise KeyError, "temperament profile is required" }
      raise ArgumentError, "temperament.profile must be non-empty text" unless temperament.is_a?(Hash) && temperament["profile"].is_a?(String) && !temperament["profile"].strip.empty?
      %w[method guardrails].each do |key|
        values = temperament[key]
        unless values.is_a?(Array) && !values.empty? && values.all? { |value| value.is_a?(String) && !value.strip.empty? }
          raise ArgumentError, "temperament.#{key} must be a non-empty list of statements"
        end
      end
      %w[delivery contexts].each do |key|
        value = temperament[key]
        raise ArgumentError, "temperament.#{key} must be a non-empty mapping" unless value.is_a?(Hash) && !value.empty?
      end
    end

    def validate_laws(data, path:, text:)
      Master::FlatLawCatalogue.validate!(data)
      catalogue = data.fetch("law_catalogue") { raise KeyError, "laws.yml requires law_catalogue" }
      validate_catalogue_contract(catalogue)
      entries = catalogue.fetch("entries")
      validate_catalogue_entries(entries, repository_root(path))
      validate_catalogue_key_duplicates(text, entries.keys)
    end

    # law_runtime.yml contains runtime configuration, never Law identities.
    # Compare with normative Law nodes and the execution catalogue so new
    # duplicates are rejected without maintaining a second ID list.
    def validate_runtime_config(data, path:)
      validate_required_runtime_config_sections(data)
      raise ArgumentError, "law_runtime.yml must not duplicate law_catalogue" if data.key?("law_catalogue")

      data_root = File.dirname(File.dirname(path))
      raise ArgumentError, "law_runtime.yml cannot find its canonical laws.yml" unless
        File.file?(File.join(data_root, "data", "laws.yml"))

      laws = Master.laws_document(root: data_root)
      catalogue = laws.fetch("law_catalogue") { raise KeyError, "laws.yml has no law_catalogue" }
      law_ids = (laws.keys.map(&:to_s) - ["law_catalogue"]) + catalogue.fetch("entries").keys.map(&:to_s)
      duplicates = data.keys.map(&:to_s) & law_ids
      raise ArgumentError, "law_runtime.yml duplicates Law identity/identities owned by laws.yml: #{duplicates.sort.join(', ')}" unless duplicates.empty?
    end

    def validate_required_runtime_config_sections(data)
      missing = REQUIRED_RUNTIME_CONFIG_SECTIONS - data.keys.map(&:to_s)
      raise ArgumentError, "required runtime configuration section(s) missing: #{missing.join(', ')}" unless missing.empty?
    end

    def validate_catalogue_contract(catalogue)
      raise ArgumentError, "law_catalogue must be a mapping" unless catalogue.is_a?(Hash)
      modalities = Array(catalogue["modalities"]).map(&:to_s).uniq.sort
      raise ArgumentError, "law_catalogue.modalities must be #{LAW_MODALITIES.join(', ')}" unless modalities == LAW_MODALITIES
      raise ArgumentError, "law_catalogue.surfaces must be non-empty" if Array(catalogue["surfaces"]).empty?
      entries = catalogue.fetch("entries") { raise KeyError, "law_catalogue.entries is required" }
      raise ArgumentError, "law_catalogue.entries must be a non-empty mapping" unless entries.is_a?(Hash) && !entries.empty?

      keys = entries.keys.map { |id| id.to_s.downcase }
      duplicates = keys.tally.select { |_id, count| count > 1 }.keys
      raise ArgumentError, "duplicate Law identities: #{duplicates.join(', ')}" unless duplicates.empty?
    end

    def validate_catalogue_entries(entries, _repo_root)
      entries.each do |id, row|
        raise ArgumentError, "Law #{id} must be a mapping" unless row.is_a?(Hash)
        # Universal by default; `universal: false` is a domain Law. Modalities are
        # the catalogue's, so an entry that names its own is narrowing them.
        raise ArgumentError, "Law #{id} universal must be true or false" unless [nil, true, false].include?(row["universal"])
        raise ArgumentError, "Law #{id} cannot narrow the catalogue's modalities" if row.key?("modalities")

        validate_catalogue_sources(id, row)
      end
    end

    def validate_catalogue_sources(id, row)
      sources = Array(row["definition_sources"]).map(&:to_s).uniq
      raise ArgumentError, "Law #{id} must name a Ruby source" if sources.empty?
      sources.each { |source| validate_catalogue_source(id, source) }
    end

    # Path syntax belongs in per-write admission. File existence belongs in the
    # whole-tree LawRegistryAudit, because one transaction may add/move the file
    # and update the catalogue in either write order.
    def validate_catalogue_source(id, source)
      valid = source.start_with?("MASTER/law/") && source.end_with?(".rb") &&
              !source.split("/").include?("..")
      raise ArgumentError, "Law #{id} has invalid source path #{source.inspect}" unless valid
    end

    def validate_catalogue_key_duplicates(text, ids)
      catalogue_start = text.index(/^law_catalogue:\s*$/)
      entries_start = text.index(/^  entries:\s*$/, catalogue_start || 0)
      raise ArgumentError, "law_catalogue.entries source section is missing" unless catalogue_start && entries_start

      declared = text[entries_start..].lines.filter_map do |line|
        match = line.match(/\A    ([A-Za-z0-9_]+):\s*\z/)
        match && match[1].downcase
      end
      expected = ids.map { |id| id.to_s.downcase }.sort
      raise ArgumentError, "Law catalogue keys are duplicated or malformed in YAML source" unless declared.sort == expected
    end

    def normalize_path(value)
      path = value.to_s.tr("\\", "/").strip
      raise ArgumentError, "sacred path must be non-empty" if path.empty?
      raise ArgumentError, "sacred path must be relative: #{path}" if path.start_with?("/") || path.match?(/\A[A-Za-z]:/)
      raise ArgumentError, "sacred path escapes its root: #{path}" if path.split("/").include?("..")

      path
    end

    def repository_root(path)
      master_root = File.dirname(File.dirname(File.expand_path(path)))
      File.dirname(master_root)
    end
  end
end
