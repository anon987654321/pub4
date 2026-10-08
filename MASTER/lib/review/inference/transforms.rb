# frozen_string_literal: true

module Master
  module Review
    module Inference
      module Transforms
        STYLES = {
          senior_engineer: "Write like a senior engineer who hunts edge cases, unnecessary machinery and hidden coupling.",
          noir_detective: "Use a restrained noir case-file voice. Change the surface style only; preserve facts and technical meaning.",
          victorian_governess: "Explain with the brisk, exacting voice of a Victorian governess addressing a chaotic household.",
          drill_sergeant: "Use a brisk drill-sergeant voice. Change the surface style only; preserve facts and technical meaning."
        }.freeze

        module_function

        def repeat(prompt)
          "#{prompt}

#{prompt}"
        end

        def self_aware(prompt)
          [
            "Before answering, give a compact decision frame:",
            "kind: what sort of task this is",
            "known: the evidence you are relying on",
            "unknown: the important uncertainty that remains",
            "tools: whether a tool or external evidence is needed",
            "Do not expose private chain-of-thought. Then answer the task.",
            prompt.to_s
          ].join("
")
        end

        def style(prompt, name)
          style = STYLES[name.to_sym] || name.to_s
          return prompt.to_s if style.empty?

          "#{style}

#{prompt}"
        end

        def rival(prompt, phase: :review)
          context = {
            planning: "A rival implementer will execute this plan and look for omissions. Make the plan exact and testable.",
            implementation: "A rival reviewer will inspect this implementation. Make every assumption explicit and remove avoidable fragility.",
            review: "This work was produced by a rival team. Review it aggressively for defects, omissions, bypasses and unnecessary complexity.",
            fixing: "A rival verifier will try to prove this fix false. Make the repair minimal, observable and hard to misread.",
            verification: "Treat every previous claim as untrusted until executable evidence proves it."
          }.fetch(phase.to_sym, "A rival verifier will try to prove this work false.")
          "#{context}

#{prompt}"
        end

        def perspective_prompt(prompt, perspective)
          {
            direct: "Reason from the direct perspective: what would the actor actually observe and decide?",
            expert: "Reason as a domain expert: what mechanism, constraint or edge case matters most?",
            observer: "Reason as an outside observer: what would an impartial reviewer conclude from the evidence?"
          }.fetch(perspective.to_sym, perspective.to_s)
            .then { |lens| "#{lens}

#{prompt}" }
        end
      end
    end
  end
end
