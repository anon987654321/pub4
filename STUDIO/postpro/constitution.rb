# frozen_string_literal: true

# The creative boundary between Postpro and MASTER law. MASTER/data/laws.yml is
# the catalogue; law/universal.rb carries the executable semantic laws after
# their migration out of the catalogue. This adapter turns the applicable laws
# into image-generation invariants rather than trying to lint aesthetics with regex.
require "fileutils"
require "json"
require_relative "../output_paths"

module Postpro
  module Constitution
    # Renders of a photograph sit beside it (output_dir_for). This dated directory
    # is only for output with no source photograph, such as an exported LUT.
    OUTPUT_DIR = Studio::OutputPaths.render_directory.freeze
    LAW_PATHS = [
      File.expand_path("../../MASTER/law/universal.rb", __dir__),
      File.expand_path("../../MASTER/law/definition.rb", __dir__),
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

    DEFAULT_VARIATION_RANGE = (5..10).freeze

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

    # The required laws live in law/*.rb, not in laws.yml's text: a law migrated
    # out of the catalogue is still a law, and only its definition can be run.
    def verify_law_catalog!
      missing = REQUIRED_LAWS.reject { |id| law_sources.match?(/Law\.define\(:#{id}\)/) }
      return true if missing.empty?

      raise ArgumentError, "MASTER constitution missing required law(s): #{missing.join(", ")}"
    end

    def verify_chain!(chain:, stage_rank:)
      verify_law_catalog!
      effects = chain.map(&:first).map(&:to_s)
      analog_count = (effects & ANALOG_CORE).uniq.length
      raise ArgumentError, "constitutional grade needs at least three analog substrate effects" if analog_count < 3

      ranks = effects.filter_map { |effect| stage_rank[effect] }
      unless ranks.length == effects.length
        raise ArgumentError, "constitutional grade contains an effect with no physical stage"
      end

      # A repeat is a second pass placed later on purpose, so order is judged on
      # each effect's first appearance.
      first_passes = effects.uniq.map { |effect| stage_rank[effect] }
      ordered = first_passes.each_cons(2).all? { |left, right| left <= right }
      raise ArgumentError, "constitutional grade breaks physical transformation order" unless ordered

      true
    end

    def verify_batch!(variation_count:, explicit_count:)
      verify_law_catalog!
      return true if explicit_count || DEFAULT_VARIATION_RANGE.cover?(variation_count)

      raise ArgumentError, "constitutional batch must generate five to ten variations per source by default"
    end

    # A render sits beside its source, always: no environment variable and no
    # location redirects it. Inside the checkout the root .gitignore keeps
    # postpro_* renders out of git, so the tree stays clean without moving them.
    def output_dir_for(source)
      File.dirname(File.expand_path(source))
    end

    # Renders are replaceable: a new family for a source removes the old one first.
    # A render belongs to a source when its sidecar names that source as its input,
    # so two photographs whose names share a prefix never touch each other's takes.
    def retire_previous_renders!(source)
      input = File.expand_path(source)
      retired = Dir.glob(File.join(output_dir_for(input), "postpro_*.json")).count do |sidecar|
        next false unless sidecar_input(sidecar) == input

        FileUtils.rm_f([sidecar.delete_suffix(".json"), sidecar])
        true
      end
      warn "postpro: removed #{retired} earlier render(s) of #{File.basename(input)}" if retired.positive?
      retired
    end

    def sidecar_input(path)
      JSON.parse(File.read(path, encoding: "UTF-8"))["input"]
    rescue JSON::ParserError, SystemCallError
      nil
    end

    # Creates the output folder and says once per folder where renders will land.
    def announce_output_dir!(directory = OUTPUT_DIR)
      @announced_output_dirs ||= []
      return if @announced_output_dirs.include?(directory)

      FileUtils.mkdir_p(directory)
      warn "postpro: renders go to #{directory}"
      @announced_output_dirs << directory
    end

    # Generated names are stable until they collide; a name still on disk keeps its
    # file and the new output takes a timestamped sibling.
    def available_output_path(output_path)
      output = File.expand_path(output_path)
      return output unless existing_output(output)

      extension = File.extname(output)
      basename = File.basename(output, extension)
      directory = File.dirname(output)
      stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%6NZ")
      index = 0
      loop do
        suffix = index.zero? ? stamp : "#{stamp}-#{index}"
        candidate = File.join(directory, "#{basename}_#{suffix}#{extension}")
        return candidate unless existing_output(candidate)

        index += 1
      end
    end

    def existing_output(path)
      [path, "#{path}.json"].find do |candidate|
        File.exist?(candidate) || File.symlink?(candidate)
      end
    end

    def verify_distinct_source!(input_path:, output_path:)
      verify_law_catalog!
      input = File.expand_path(input_path)
      output = File.expand_path(output_path)
      same_file = input == output
      if !same_file && File.exist?(input) && File.exist?(output)
        source_stat = File.stat(input)
        output_stat = File.stat(output)
        same_file = source_stat.dev == output_stat.dev && source_stat.ino == output_stat.ino
      end
      raise ArgumentError, "constitutional output would overwrite the source" if same_file

      true
    end

    def verify_output!(input_path:, output_path:)
      input = File.expand_path(input_path)
      output = File.expand_path(output_path)
      verify_distinct_source!(input_path: input, output_path: output)
      unless File.dirname(output) == output_dir_for(input)
        raise ArgumentError, "constitutional output must sit beside its source"
      end

      unless File.basename(output).start_with?("postpro_")
        raise ArgumentError, "constitutional output must use postpro_ prefix"
      end
      existing = existing_output(output)
      if existing
        raise ArgumentError, "constitutional output already exists: #{File.basename(existing)}"
      end

      announce_output_dir!(File.dirname(output))
      true
    end
  end
end
