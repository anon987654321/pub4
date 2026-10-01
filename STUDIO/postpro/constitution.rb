# frozen_string_literal: true

# The creative boundary between Postpro and MASTER law. MASTER/data/rules.yml is
# the catalogue; law/universal.rb carries the executable semantic laws after
# their migration out of the catalogue. This adapter turns the applicable laws
# into image-generation invariants rather than trying to lint aesthetics with regex.
module Postpro
  module Constitution
    OUTPUT_DIR = File.expand_path(ENV.fetch("POSTPRO_OUTPUT_DIR", __dir__)).freeze
    RULES_PATH = File.expand_path("../../MASTER/data/rules.yml", __dir__).freeze
    LAW_PATHS = [
      File.expand_path("../../MASTER/law/universal.rb", __dir__),
      File.expand_path("../../MASTER/law/law.rb", __dir__),
    ].freeze

    REQUIRED_LAWS = %w[
      ONE_SOURCE
      NO_SIDE_EFFECTS
      TRANSFORMATIONS
      ANALOG_WARMTH
      MASS_GENERATE_CURATE
      USER_CONTROL
      DOMAIN_LANGUAGE
    ].freeze

    ANALOG_CORE = %w[
      film_curve
      grain
      halation
      stock_matrix
      dir_coupler
      adjacency_effects
      film_base_density
      orange_mask
      print_film
      dilla_head_bump
      dilla_tape_saturation
      dilla_vinyl_bandlimit
      dilla_phasy
      dilla_console_sum
    ].freeze

    module_function

    def law_sources
      @law_sources ||= (LAW_PATHS.map { |path| File.read(path, encoding: "UTF-8") }.join("\n")).freeze
    end

    def rules_catalog
      @rules_catalog ||= File.read(RULES_PATH, encoding: "UTF-8").freeze
    end

    def verify_law_catalog!
      missing = REQUIRED_LAWS.reject { |id| rules_catalog.include?(id) && law_sources.match?(/Law\.define\(:#{id}\)/) }
      return true if missing.empty?

      raise ArgumentError, "MASTER constitution missing required law(s): #{missing.join(", ")}"
    end

    def verify_chain!(chain:, stage_rank:)
      verify_law_catalog!
      effects = chain.map(&:first).map(&:to_s)
      analog_count = (effects & ANALOG_CORE).uniq.length
      raise ArgumentError, "constitutional grade needs at least three analog substrate effects" if analog_count < 3

      ranks = effects.filter_map { |effect| stage_rank[effect] }
      raise ArgumentError, "constitutional grade contains an effect with no physical stage" if ranks.length != effects.length
      raise ArgumentError, "constitutional grade breaks physical transformation order" unless ranks.each_cons(2).all? { |left, right| left <= right }

      true
    end

    def verify_batch!(variation_count:, explicit_count:)
      verify_law_catalog!
      return true if explicit_count || RANDOM_VARIATION_RANGE.cover?(variation_count)

      raise ArgumentError, "constitutional batch must generate five to ten variations per source by default"
    end

    def verify_output!(input_path:, output_path:)
      verify_law_catalog!
      input = File.expand_path(input_path)
      output = File.expand_path(output_path)
      raise ArgumentError, "constitutional output would overwrite the source" if input == output
      raise ArgumentError, "constitutional output must stay in the Postpro output directory" unless File.dirname(output) == OUTPUT_DIR
      raise ArgumentError, "constitutional output must use postpro_ prefix" unless File.basename(output).start_with?("postpro_")
      true
    end
  end
end
