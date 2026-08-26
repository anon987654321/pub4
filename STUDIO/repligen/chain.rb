# frozen_string_literal: true

require "yaml"

# A chain is several models in a row, where each stage's output is the next
# stage's input.
#
# repligen was single-shot: one model, one prompt, optionally one --postpro
# handoff at the end. That is enough to make a picture and not enough to make
# one nobody has seen, because a single model produces the look it was trained
# to produce. What produces an unfamiliar image is passing a frame through
# several models that disagree about what an image is.
#
# The FLUX 2 family is unusually suited to it, and the reason is worth stating
# because it decides how a chain should be written: those models are decomposed
# by what they PRESERVE. flux-depth-pro holds 3D spatial relationships while the
# surface changes completely; flux-canny-pro holds edges; flux-fill-pro holds
# the surroundings; flux-2-max holds a character across a batch from up to eight
# reference images. They are not five ways to make a picture. They are five ways
# to change one thing while holding a different invariant — which is exactly
# what a chain needs, because a chain of stages that each preserve nothing
# converges on mush by stage four.
#
# The validation here matters more than the execution. repligen's whole design
# is to refuse an option a model does not accept rather than let the API ignore
# it, because a request that "works" while silently dropping a setting is far
# harder to notice than a 422. A chain multiplies that: stage 6 failing because
# stage 2 could not produce what stage 3 assumed is a bad afternoon and a real
# bill. So a chain is validated whole, before anything is spent.
module Repligen
  module Chain
    Stage = Struct.new(:name, :model, :prompt, :inherits, :options, keyword_init: true)

    # What a stage can take from the one before it. `image` is the common case —
    # the previous output becomes this stage's input_image — and `references`
    # is the multi-reference consistency spine that stops long chains drifting.
    INHERITABLE = %w[image references seed prompt].freeze

    DEFAULT_DIR = File.join(__dir__, "chains")

    class Invalid < StandardError; end

    def self.load(name, dir: DEFAULT_DIR)
      path = File.join(dir, "#{name}.yml")
      raise Invalid, "no chain named #{name} in #{dir}" unless File.file?(path)

      parse(YAML.safe_load_file(path), name: name)
    end

    def self.available(dir: DEFAULT_DIR)
      Dir.glob(File.join(dir, "*.yml")).map { |p| File.basename(p, ".yml") }.sort
    end

    def self.parse(doc, name:)
      raise Invalid, "chain #{name} has no stages" unless doc.is_a?(Hash) && doc["stages"].is_a?(Array)
      raise Invalid, "chain #{name} has an empty stage list" if doc["stages"].empty?

      stages = doc["stages"].each_with_index.map do |row, index|
        raise Invalid, "chain #{name} stage #{index + 1} is not a mapping" unless row.is_a?(Hash)

        Stage.new(
          name: row.fetch("name") { "stage_#{index + 1}" },
          model: row["model"],
          prompt: row["prompt"],
          inherits: Array(row["inherits"]),
          options: (row["options"] || {}).transform_keys(&:to_sym)
        )
      end
      { name: name, description: doc["description"], stages: stages }
    end

    # Everything wrong with the chain, as a list, before a single request is
    # made. A list rather than the first problem, because fixing them one
    # provider round-trip at a time is the thing this exists to prevent.
    #
    # `capability_for` is passed in rather than reached for: this file is loaded
    # by the tests without loading the CLI, and a hard reference to a top-level
    # method defined in repligen.rb would make that impossible.
    def self.problems(chain, capability_for:)
      found = []
      stages = chain.fetch(:stages)

      stages.each_with_index do |stage, index|
        position = "stage #{index + 1} (#{stage.name})"
        found << "#{position} names no model" if stage.model.to_s.strip.empty?
        next if stage.model.to_s.strip.empty?

        cap = capability_for.call(stage.model)
        keys = Array(cap[:input_keys])

        stage.inherits.each do |what|
          unless INHERITABLE.include?(what)
            found << "#{position} inherits #{what.inspect}, which is not one of #{INHERITABLE.join(', ')}"
            next
          end
          if index.zero?
            found << "#{position} is first and inherits #{what.inspect}, but nothing has run yet"
            next
          end
          # The refusal that matters: a stage that expects an image from the one
          # before it, handed to a model with nowhere to put an image.
          # Either spelling. FLUX 1 editors take a single `input_image`; FLUX 2
          # takes `input_images`, a list of up to eight it holds a character
          # across. Checking only the singular would have refused every FLUX 2
          # chain — correctly by its own rule, and wrongly in fact.
          if what == "image" && (keys & %w[input_image input_images]).empty?
            found << "#{position} inherits the previous image, but #{stage.model} declares neither " \
                     "input_image nor input_images — it would silently generate from the prompt alone"
          end
        end

        stage.options.each_key do |opt|
          next if keys.include?(opt.to_s)
          next if %i[negative postpro].include?(opt)

          found << "#{position} sets #{opt}, which #{stage.model} does not accept"
        end

        found << "#{position} has neither a prompt nor an inherited one" if
          stage.prompt.to_s.strip.empty? && !stage.inherits.include?("prompt")
      end

      found << "chain #{chain[:name]} never preserves structure — every stage generates from " \
               "scratch, which drifts. Consider a depth, canny or fill stage, or inherit " \
               "references." if stages.length > 2 && stages.none? { |s| s.inherits.any? }

      found
    end

    # Run the stages, carrying forward what each one declares it inherits.
    #
    # `perform` is injected rather than called directly, for the same reason
    # capability_for is: this is the path that spends money, and a loop that can
    # only be exercised by spending it is a loop nobody checks. The tests hand in
    # a recorder and assert the carry-forward — that stage N+1 is actually given
    # stage N's file, which is the one thing a chain has to get right and the one
    # thing that fails silently, because a model handed no image generates
    # from the prompt and returns something plausible.
    #
    # Returns the files produced, in order. Every intermediate is kept: a chain
    # is worth running because of what happens between stages, and a run that
    # discards stage 2 cannot tell you that stage 2 was where the look was won.
    def self.run(chain, perform:, until_stage: nil, image: nil, seed: nil)
      carried_image = image
      carried_seed = seed
      produced = []

      chain.fetch(:stages).each_with_index do |stage, index|
        inherited_image = stage.inherits.include?("image") ? carried_image : nil
        inherited_seed = stage.inherits.include?("seed") ? carried_seed : nil

        result = perform.call(
          stage: stage, index: index, total: chain[:stages].length,
          image: inherited_image, seed: inherited_seed
        )
        break if result.nil?

        produced << result[:path]
        carried_image = result[:path]
        carried_seed = result[:seed] if result[:seed]
        break if until_stage && until_stage == stage.name
      end

      produced
    end

    # What will happen, in order, without doing it.

    def self.plan(chain)
      chain.fetch(:stages).each_with_index.map do |stage, index|
        carried = stage.inherits.empty? ? "nothing" : stage.inherits.join(" + ")
        opts = stage.options.empty? ? "" : "  [#{stage.options.map { |k, v| "#{k}=#{v}" }.join(' ')}]"
        format("  %2d. %-22s %-38s carries: %s%s",
               index + 1, stage.name.to_s, stage.model.to_s, carried, opts)
      end
    end
  end
end
