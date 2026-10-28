# frozen_string_literal: true

require "yaml"
require_relative "law_vocabulary"
require_relative "provider_catalogue_guard"
require_relative "model_catalogue_guard"
require_relative "io/dynamic_tools"

module Master
  # Validates the governing YAML by its invariants. Who may write it is a
  # separate question soul.yml's sacred_paths answer: no automated writer may,
  # and a person commits it with ordinary git. These invariants judge every
  # candidate either way, so a write that is let through is still a valid one.
  module ConfigurationGuard
    module_function

    LAW_MODALITIES = LawVocabulary::MODALITIES

    REQUIRED_LAW_SECTIONS = %w[
      CAPABILITY_STATUS_MUST_BE_TRUTHFUL ROBUSTNESS SINGULARITY LINEARITY
      PROXIMITY ABSTRACTION DENSITY RENDERED_VALUES INTER_MODEL_CONTRACT
      veto_patterns law_map transformation_policy law_catalogue
    ].freeze
    # Sacred means no automated writer may change the path. The whole data/
    # directory cannot be: tokens, state and ratchet ceilings there are written
    # by the runtime every day. Nor can the retired scanner directories, which
    # would freeze scanner code that must evolve.
    TOO_BROAD_SACRED_PATHS = %w[
      data/ data lib/review/scan/ lib/review/scan/laws lib/review/scan/laws/
    ].freeze
    LIVE_SOUL = File.expand_path("../data/soul.yml", __dir__)
    REQUIRED_TOKEN_MAPS = %w[
      visual_identity viewport shared_chrome system storefront_art radio luxury promotional_art
      face_root face_interface brgen_old_dark brgen_old_light openbsd_wscons social light
      vertical_accents scale layout_rules kinetic_depth visual_design motion_and_sound
      data_visualization automated_css_analysis ux_laws typography worn_type pixel_perfection
      rams_checklist ui_polish pwa ultraminimalism ad_visual_contract brand_systems
    ].freeze
    TOKEN_ROOT_FIELDS = %w[tokens].freeze
    def validate(path:, content:, root: nil)
      absolute = File.expand_path(path.to_s, root || Dir.pwd)
      kind = kind_for(absolute)
      return unless kind

      if kind == :dynamic_tools
        Master::Io::DynamicTools.validate_source(content, path: absolute)
        return nil
      end

      data = YAML.safe_load(content, aliases: true)
      raise ArgumentError, "top-level YAML value must be a mapping" unless data.is_a?(Hash)

      case kind
      when :laws then validate_laws(data, path: absolute, text: content)
      when :soul then validate_soul(data, path: absolute)
      when :providers then ProviderCatalogueGuard.validate(data)
      when :models then ModelCatalogueGuard.validate(data, path: absolute)
      when :tokens then validate_tokens(data)
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
      return :soul if normalized.match?(%r{/MASTER/data/soul\.yml\z})
      return :providers if normalized.match?(%r{/MASTER/data/providers\.yml\z})
      return :models if normalized.match?(%r{/MASTER/data/models\.yml\z})
      return :tokens if normalized.match?(%r{/MASTER/data/tokens\.yml\z})
      return :dynamic_tools if normalized.match?(%r{/MASTER/data/tools\.dynamic\.yml\z})

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
         radius_xs radius_sm radius_md radius_card radius_lg radius_pill].each do |field|
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
      absolute = data.fetch("absolute") { raise KeyError, "absolute section is required" }
      raise ArgumentError, "absolute section must be a mapping" unless absolute.is_a?(Hash)
      unless absolute["golden_law"] == "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        raise ArgumentError, "golden_law must remain PRESERVE_THEN_IMPROVE_NEVER_BREAK"
      end

      validate_sacred_paths(Array(absolute["sacred_paths"]).map { |entry| normalize_path(entry) }, path)
    end

    def validate_sacred_paths(paths, path)
      raise ArgumentError, "sacred_paths must not be empty" if paths.empty?

      broad = paths.select { |entry| TOO_BROAD_SACRED_PATHS.include?(entry) }
      unless broad.empty?
        raise ArgumentError, "runtime-written data and retired scanner paths cannot be sacred: #{broad.join(', ')}"
      end

      missing = live_sacred_paths(path) - paths
      raise ArgumentError, "critical path protections missing: #{missing.join(', ')}" unless missing.empty?
    end

    # soul.yml is the one list. A candidate keeps every path the soul it replaces
    # declares, so no validated write can drop a protection; a person removes one
    # with an ordinary commit. A candidate for a file not yet written is held to
    # this MASTER's soul.
    def live_sacred_paths(path)
      soul = YAML.safe_load_file(File.file?(path) ? path : LIVE_SOUL, aliases: true)
      declared = soul.is_a?(Hash) && soul["absolute"].is_a?(Hash) ? soul["absolute"]["sacred_paths"] : nil

      Array(declared).map { |entry| normalize_path(entry) }
    end

    def validate_laws(data, path:, text:)
      validate_required_law_sections(data)
      catalogue = data.fetch("law_catalogue")
      validate_catalogue_contract(catalogue)
      entries = catalogue.fetch("entries")
      validate_catalogue_entries(entries, repository_root(path))
      validate_catalogue_key_duplicates(text, entries.keys)
    end

    def validate_required_law_sections(data)
      missing = REQUIRED_LAW_SECTIONS - data.keys.map(&:to_s)
      raise ArgumentError, "required Law sections missing: #{missing.join(', ')}" unless missing.empty?
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

    def validate_catalogue_entries(entries, repo_root)
      entries.each do |id, row|
        raise ArgumentError, "Law #{id} must be a mapping" unless row.is_a?(Hash)
        raise ArgumentError, "Law #{id} must be universal" unless row["universal"] == true
        modalities = Array(row["modalities"]).map(&:to_s).uniq.sort
        raise ArgumentError, "Law #{id} modalities must be #{LAW_MODALITIES.join(', ')}" unless modalities == LAW_MODALITIES

        validate_catalogue_sources(id, row)
      end
    end

    def validate_catalogue_sources(id, row)
      sources = (Array(row["definition_sources"]) + Array(row["detector_sources"])).map(&:to_s).uniq
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
