# frozen_string_literal: true

module Master
  module Review
    module Inference
      module Search
        module_function

        def self_consistency(agent:, prompt:, samples:, temperature:, extractor:)
          paths = parallel(agent, Array.new(samples) { prompt }, temperature:)
          return Master::Result.err("inference: self-consistency produced no paths") if paths.empty?

          answers = paths.map { |path| extractor.call(path) }.map { |answer| answer.to_s.strip }.reject(&:empty?)
          return Master::Result.err("inference: self-consistency extracted no answers") if answers.empty?

          tally = answers.tally
          winner, votes = tally.max_by { |answer, count| [count, answer] }
          Master::Result.ok(
            strategy: :self_consistency,
            winner:,
            votes: tally,
            confidence: votes.to_f / answers.size,
            paths:
          )
        rescue StandardError => e
          Master::Result.err("inference: self-consistency #{e.class}: #{e.message}", category: :handler_exception)
        end

        def skeleton(agent:, prompt:, points:, temperature:)
          skeleton = ask(agent, "List #{points} independent answer points for this task, one numbered point per line. Do not expand them yet.\n\n#{prompt}")
          return skeleton if skeleton.is_a?(Master::Result::Err)

          items = parse_points(skeleton).first(points)
          return Master::Result.err("inference: skeleton produced no points") if items.empty?

          expanded = parallel(
            agent,
            items.map { |item| "Expand this answer point into precise, self-contained content.\n\nPoint: #{item}\n\nTask: #{prompt}" },
            temperature:
          )
          synthesis = ask(
            agent,
            "Synthesize the following independent sections into one coherent answer. Remove duplicated claims and preserve all material evidence.\n\nTask: #{prompt}\n\nSections:\n#{expanded.join("\n\n---\n\n")}"
          )
          return synthesis if synthesis.is_a?(Master::Result::Err)

          Master::Result.ok(strategy: :skeleton, skeleton: items, expanded:, final: synthesis)
        rescue StandardError => e
          Master::Result.err("inference: skeleton #{e.class}: #{e.message}", category: :handler_exception)
        end

        def tree(agent:, prompt:, branches:, beam:, depth:, temperature:)
          frontier = [{ state: prompt, score: 0.0, path: [] }]
          leaves = []

          depth.times do |level|
            candidates = frontier.flat_map do |node|
              raw = ask(
                agent,
                "Given the current problem state below, propose #{branches} materially different next moves. "                 "Each move must be a complete candidate state, not a commentary on the alternatives.\n\n"                 "Depth: #{level + 1}\nState:\n#{node[:state]}"
              )
              next [] if raw.is_a?(Master::Result::Err)

              parse_points(raw).first(branches).map do |candidate|
                { state: candidate, path: node[:path] + [candidate], parent: node[:state] }
              end
            end

            break if candidates.empty?

            scored = candidates.map do |candidate|
              score = ask(
                agent,
                "Score this candidate state from 0.0 to 1.0 for correctness, progress, simplicity and fit to the original problem. "                 "Return one decimal number only. Original problem: #{prompt}\n\nCandidate: #{candidate[:state]}"
              )
              value = score.is_a?(Master::Result::Err) ? 0.0 : numeric_score(score)
              candidate.merge(score: value)
            end

            frontier = scored.sort_by { |candidate| [-candidate[:score], candidate[:state]] }.first(beam)
            leaves.concat(frontier)
          end

          best = leaves.max_by { |candidate| [candidate[:score], candidate[:state]] }
          return Master::Result.err("inference: tree search found no candidate") unless best

          Master::Result.ok(strategy: :tree_of_thoughts, best:, leaves:)
        rescue StandardError => e
          Master::Result.err("inference: tree search #{e.class}: #{e.message}", category: :handler_exception)
        end

        def parallel(agent, prompts, temperature:)
          threads = prompts.map { |prompt| Thread.new { agent.ask_once(prompt, temperature:) } }
          threads.map(&:value)
        end
        private_class_method :parallel

        def ask(agent, prompt)
          agent.ask_once(prompt)
        rescue StandardError => e
          Master::Result.err("inference: call failed: #{e.message}", category: :llm_call_failure)
        end
        private_class_method :ask

        def parse_points(text)
          text.to_s.lines.filter_map do |line|
            value = line.sub(/^\s*(?:[-*]|\d+[.)])\s*/, "").strip
            value unless value.empty?
          end
        end
        private_class_method :parse_points

        def numeric_score(text)
          match = text.to_s.match(/\b(?:0(?:\.\d+)?|1(?:\.0+)?)\b/)
          match ? match[0].to_f : 0.0
        end
        private_class_method :numeric_score
      end
    end
  end
end
