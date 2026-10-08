# frozen_string_literal: true

require "digest"

module Master
  module Review
    module Inference
      module Novelty
        PERSPECTIVES = %i[direct expert observer].freeze
        DEBATE_ROLES = {
          logician: "Prioritise correctness, explicit assumptions and contradictions.",
          engineer: "Prioritise feasibility, failure modes, maintainability and cost.",
          contrarian: "Assume the obvious approach is wrong and hunt for a materially different mechanism."
        }.freeze

        module_function

        def denial(agent:, prompt:, constraints:, rounds:, temperature:)
          answers = []
          current = prompt.to_s

          rounds.times do |index|
            answer = agent.ask_once(current, temperature:)
            answers << answer
            constraint = Array(constraints)[index % Array(constraints).length]
            break unless constraint

            current = [
              prompt,
              "Previous candidate:",
              answer,
              "Deny that approach now. Produce a materially different solution.",
              "Forbidden approach: #{constraint}"
            ].join("

")
          end

          Master::Result.ok(strategy: :denial, rounds: answers.size, answers:)
        rescue StandardError => e
          Master::Result.err("inference: denial #{e.class}: #{e.message}", category: :handler_exception)
        end

        def strange_world(agent:, problem:, seeds:, temperature:)
          choices = Array(seeds).map(&:to_s).reject(&:empty?)
          return Master::Result.err("inference: strange world has no seeds") if choices.empty?

          index = Digest::SHA256.hexdigest(problem.to_s)[0, 8].to_i(16) % choices.length
          seed = choices[index]

          world = agent.ask_once(
            "You are a world builder. You see only the seed word below. Build a coherent alternative world with 3-5 precise rules of physics, causality, information or incentives. "             "Do not ask what problem this is for.\n\nSeed: #{seed}",
            temperature:
          )
          solution = agent.ask_once(
            "Solve the problem inside the strange world below. Obey its rules even when they are inconvenient. Produce several mechanisms that exploit the altered assumptions.\n\nWorld:\n#{world}\n\nProblem:\n#{problem}",
            temperature:
          )
          evaluation = agent.ask_once(
            "Evaluate these strange-world mechanisms against the original problem. Extract only insights that remain useful after returning to the real world. Reject decorative novelty.\n\nProblem:\n#{problem}\n\nMechanisms:\n#{solution}",
            temperature:
          )

          Master::Result.ok(strategy: :strange_world, seed:, world:, solutions: solution, evaluation:)
        rescue StandardError => e
          Master::Result.err("inference: strange world #{e.class}: #{e.message}", category: :handler_exception)
        end

        def quadrant_vacancy(agent:, theme:, samples:, temperature:, fill_limit: 4)
          generated = samples.to_i.times.map do
            agent.ask_once("Generate one materially different solution to this theme. Do not restate another archetype.\n\nTheme: #{theme}", temperature:)
          end
          return Master::Result.err("inference: QVP generated no samples") if generated.empty?

          axes = agent.ask_once(
            "Find two meaningfully different, roughly orthogonal dimensions that separate the candidate solutions below. "             "Return exactly two lines: X: low -> high and Y: low -> high.\n\n#{generated.join("\n\n")}",
            temperature:
          )
          mapped = agent.ask_once(
            "Map each numbered candidate onto the X/Y plane. Use only LOW or HIGH for each axis. "             "Return one line per candidate: N X=LOW|HIGH Y=LOW|HIGH.\n\nAxes:\n#{axes}\n\n#{numbered(generated)}",
            temperature:
          )
          grid = parse_grid(mapped, generated.length)
          vacancies = %w[LOW/LOW LOW/HIGH HIGH/LOW HIGH/HIGH].reject { |cell| grid.include?(cell) }.first(fill_limit.to_i)

          fillings = vacancies.map do |cell|
            agent.ask_once(
              "Generate a solution that deliberately occupies this currently vacant quadrant. "               "Stay faithful to the theme and make the mechanism genuinely different from the supplied candidates.\n\n"               "Theme: #{theme}\nAxes:\n#{axes}\nVacancy: #{cell}",
              temperature:
            )
          end

          Master::Result.ok(strategy: :quadrant_vacancy, axes:, samples: generated, map: grid, vacancies:, fillings:)
        rescue StandardError => e
          Master::Result.err("inference: QVP #{e.class}: #{e.message}", category: :handler_exception)
        end

        def perspective(agent:, prompt:, temperature:)
          views = PERSPECTIVES.to_h do |perspective|
            [perspective, agent.ask_once(Transforms.perspective_prompt(prompt, perspective), temperature:)]
          end
          judge = agent.ask_once(
            "Compare these three perspectives on the same task. Pick the perspective that yields the strongest evidence-backed answer and say why in one paragraph. Then provide the final answer.\n\n"             views.map { |name, text| "#{name}:\n#{text}" }.join("\n\n---\n\n"),
            temperature:
          )

          Master::Result.ok(strategy: :perspective_transition, perspectives: views, final: judge)
        rescue StandardError => e
          Master::Result.err("inference: perspective transition #{e.class}: #{e.message}", category: :handler_exception)
        end

        def debate(agent:, prompt:, rounds:, temperature:)
          answers = DEBATE_ROLES.to_h do |role, brief|
            [role, agent.ask_once("#{brief}\n\nQuestion:\n#{prompt}", temperature:)]
          end

          rounds.to_i.times do
            answers = DEBATE_ROLES.keys.to_h do |role|
              others = answers.reject { |name, _| name == role }
              context = others.map { |name, answer| "#{name}:\n#{answer}" }.join("\n\n")
              [
                role,
                agent.ask_once(
                  "#{DEBATE_ROLES.fetch(role)}\n\nQuestion:\n#{prompt}\n\nYour prior answer:\n#{answers.fetch(role)}\n\nOther positions:\n#{context}\n\nReconsider them. Change your answer only where their evidence beats yours.",
                  temperature:
                )
              ]
            end
          end

          synthesis = agent.ask_once(
            "Synthesize a final answer from the debate below. Preserve genuine disagreements until evidence resolves them. Do not reward agreement for its own sake.\n\nQuestion:\n#{prompt}\n\n#{answers.map { |role, answer| "#{role}:\n#{answer}" }.join("\n\n---\n\n")}",
            temperature:
          )
          Master::Result.ok(strategy: :debate, positions: answers, final: synthesis)
        rescue StandardError => e
          Master::Result.err("inference: debate #{e.class}: #{e.message}", category: :handler_exception)
        end

        def critique_revision(agent:, prompt:, rounds:, temperature:)
          current = agent.ask_once(prompt, temperature:)

          rounds.to_i.times do
            critique = agent.ask_once(
              "Critique the candidate below against the original task. Find concrete errors, omissions, hidden assumptions and simpler alternatives. Do not rewrite it yet.\n\nTask:\n#{prompt}\n\nCandidate:\n#{current}",
              temperature:
            )
            revised = agent.ask_once(
              "Revise the candidate using every valid point in the critique. Preserve correct material and remove unsupported claims.\n\nTask:\n#{prompt}\n\nCandidate:\n#{current}\n\nCritique:\n#{critique}",
              temperature:
            )
            break if revised.to_s.strip == current.to_s.strip

            current = revised
          end

          Master::Result.ok(strategy: :critique_revision, final: current)
        rescue StandardError => e
          Master::Result.err("inference: critique revision #{e.class}: #{e.message}", category: :handler_exception)
        end

        def novelty(agent:, prompt:, constraints:, seeds:, temperature:)
          denial_result = denial(agent:, prompt:, constraints:, rounds: 2, temperature:)
          return denial_result if denial_result.err?

          world_result = strange_world(agent:, problem: prompt, seeds:, temperature:)
          return world_result if world_result.err?

          synthesis = agent.ask_once(
            "Synthesize the strongest genuinely different ideas from the two explorations below. "             "Return one concise idea per bullet. Eliminate near-duplicates, decorative novelty and ideas that violate the stated constraints.\n\n"             "Denial exploration:\n#{denial_result.value![:answers].join("\n\n")}\n\n"             "Strange-world evaluation:\n#{world_result.value![:evaluation]}",
            temperature:
          )
          Master::Result.ok(
            strategy: :novelty,
            denial: denial_result.value!,
            strange_world: world_result.value!,
            final: synthesis
          )
        rescue StandardError => e
          Master::Result.err("inference: novelty #{e.class}: #{e.message}", category: :handler_exception)
        end

        def numbered(values)
          values.each_with_index.map { |value, index| "#{index + 1}. #{value}" }.join("\n")
        end
        private_class_method :numbered

        def parse_grid(text, count)
          text.to_s.lines.first(count).filter_map do |line|
            match = line.match(/\b(\d+)\b.*?X\s*=\s*(LOW|HIGH).*?Y\s*=\s*(LOW|HIGH)/i)
            match && [match[1].to_i, "#{match[2].upcase}/#{match[3].upcase}"]
          end.to_h.values
        end
        private_class_method :parse_grid
      end
    end
  end
end
