# frozen_string_literal: true

module Master
  module Review
    module Council
      module QualityFramework
        DEFAULT_QUESTIONS = {
          "assumptions" => [
            "which assumptions are false?",
            "if a key assumption flips what still works?",
            "which assumptions have we never tested?",
            "what happens if the opposite is true?",
            "which assumptions are load-bearing vs convenience?",
            "how do we validate assumptions incrementally?",
          ],
          "failure_modes" => [
            "how does this fail catastrophically?",
            "what breaks first under load or outage?",
            "which single point of failure is most likely?",
            "what happens when it fails silently?",
            "how do cascading failures propagate?",
            "what are blast radius containment strategies?",
          ],
          "attacker" => [
            "what does an attacker do here?",
            "where do attackers abuse or poison inputs?",
            "which trust boundaries are weakest?",
            "how do we exploit this ourselves?",
            "what attack vectors are we not considering?",
            "how do we defend against insider threats?",
          ],
          "scale" => [
            "what happens at 10x users or data?",
            "what performance cliff exists and where?",
            "which bottleneck shows up first?",
            "how does complexity grow with scale?",
            "what are the economics at different scales?",
            "which architectural decisions become problematic at scale?",
          ],
          "degradation" => [
            "how do we degrade gracefully?",
            "what is minimal viable behavior under stress?",
            "which features can we sacrifice first?",
            "how do we maintain core function during failure?",
            "what are UX implications of degradation?",
            "how do we communicate degraded service to users?",
          ],
          "edge_cases" => [
            "which edge cases do users hit first?",
            "which rare but high-impact case lacks handling?",
            "what happens with malformed inputs?",
            "how do we handle impossible combinations?",
            "which edge cases become common at scale?",
            "what edge cases exist in integration points?",
          ],
          "ops_maint" => [
            "what is long-term maintenance burden?",
            "how do we observe debug and rollback quickly?",
            "which operational complexity is hidden?",
            "how do we troubleshoot under pressure?",
            "what skills and knowledge does operations require?",
            "how do we prevent operational knowledge from being siloed?",
          ],
          "compliance_ethics" => [
            "any privacy safety or fairness risks?",
            "which regulations apply and how prove compliance?",
            "what are ethical implications?",
            "how audit and demonstrate adherence?",
            "what happens when regulations change?",
            "how balance compliance with innovation?",
          ],
          "a11y_ux" => [
            "is it operable by keyboard and screen readers?",
            "what happens with reduced motion or low bandwidth?",
            "how does this work for colorblind users?",
            "does assistive technology work with this?",
            "what are multilingual and cultural considerations?",
            "how test accessibility with actual users?",
          ],
          "economics" => [
            "where is waste or needless complexity?",
            "what is ROI vs simpler alternatives?",
            "which costs are hidden or deferred?",
            "how optimize for total cost of ownership?",
            "what are opportunity costs of this approach?",
            "how do economics change over time and scale?",
          ],
          "clarity" => [
            "is the intent obvious from names alone?",
            "which concept lacks a name and should have one?",
            "where does the code lie about what it does?",
            "what does a fresh reader misread first?",
            "which generic names hide domain meaning?",
          ],
          "evidence" => [
            "what evidence proves this works?",
            "which test fails if this is wrong?",
            "which claim lacks support?",
            "what falsifies this approach?",
          ],
          "scope" => [
            "what can we delete without loss?",
            "which abstraction is premature?",
            "what is the smallest reversible change?",
            "where did implementation exceed the need?",
          ],
          "bottlenecks" => [
            "where is the Big-O bottleneck?",
            "what allocates in the hot path?",
            "what happens to latency at p95 and p99?",
            "which work can we skip, cache, stream, or defer?",
          ],
          "consistency" => [
            "where can data go inconsistent?",
            "what is the source of truth?",
            "which names describe the same concept?",
            "which migration or state transition is not reversible?",
          ],
          "harm" => [
            "who does this harm when misused?",
            "which privacy boundary does this cross?",
            "what content or user data must remain untouched?",
            "what compliance proof do we need?",
          ],
          "visual" => [
            "where does the eye land first, and is that the right place?",
            "which element can we remove without losing meaning?",
            "does spacing prove grouping, or only decorate?",
            "which values violate the type scale, grid, or contrast rules?",
            "does the layout use absence as material?",
          ],
          "sound" => [
            "what should be foreground, background, or silent?",
            "does timing breathe, or is everything quantized to death?",
            "can sound mask speech, screen readers, or the user's task?",
            "is there a mute path and graceful media failure?",
            "which sound event communicates state instead of decoration?",
          ],
        }.freeze

        BRIEFS = {
          general: [
            "questions over commands; evidence over opinion; execution over explanation",
            "content integrity, critical security, accessibility, and reversibility are hard gates",
            "prefer surgical, reversible changes; preserve working behavior and user-curated content",
            "generate alternatives, red-team assumptions, then cherry-pick the simplest validated option",
          ].freeze,
          code: [
            "DRY after the third duplication; KISS when complexity exceeds 10; YAGNI for unused constructs",
            "SOLID boundaries: one reason to change, composition over inheritance, injected dependencies",
            "Ruby style: guard clauses, semantic names, no generic manager/handler/util names",
            "quality targets: complexity <= 10, nesting <= 4, duplication <= 3%, coverage >= 80%",
          ].freeze,
          design: [
            "typography is design: 45-75ch lines, 1.4-1.6 body leading, 16px minimum body text",
            "use an 8px spacing rhythm, 12-column structure, 44px touch minimum, and visible focus",
            "ultraminimalism: remove ornament until only hierarchy, alignment, type, and whitespace remain",
            "limit palette and type variety; reject non-token visual values and arbitrary decoration",
          ].freeze,
          sound: [
            "sound is feedback, not surprise: no autoplay without intent and mute must exist",
            "preserve silence; sounds need attack/decay/timing and must not mask speech or screen readers",
            "foreground sound is for critical state changes; midground for confirmations; background is optional",
            "prefer tiny browser-native tones/assets and graceful failure over heavy dependencies",
            "for rendered music: pad body must read above sub; HF air and presence for kit click; crest 4–10",
            "generate 3 solutions per issue then cherry-pick; prefer existing ENV/bus knobs over new systems",
          ].freeze,
        }.freeze

        PERSONA_DOMAIN = {
          "Graphic Designer" => :design,
          "Web Designer" => :design,
          "Motion Designer" => :design,
          "Google CSS Engineer" => :design,
          "NNGroup UX Researcher" => :design,
          "Typographer" => :design,
          "Cognitive Psychologist" => :design,
          "Accessibility" => :design,
          "Electronic Music Producer" => :sound,
          "Hip-Hop Producer" => :sound,
          "Sound Designer" => :sound,
          "Sound Engineer" => :sound,
          "Label Executive" => :sound,
          "Organ Composer" => :sound,
          "Security" => :code,
          "Reliability" => :code,
          "Maintainer" => :code,
          "Performance" => :code,
          "QA Engineer" => :code,
        }.freeze

        def self.questions
          council = if File.exist?(Deliberation::Master::COUNCIL_PATH)
                      Master.load_yaml(Deliberation::Master::COUNCIL_PATH).fetch("questions", {})
                    else
                      {}
                    end
          DEFAULT_QUESTIONS.merge(council) { |_key, builtin, custom| (Array(builtin) + Array(custom)).uniq }
        rescue StandardError
          DEFAULT_QUESTIONS
        end

        def self.domain_for(persona_name)
          PERSONA_DOMAIN.fetch(persona_name.to_s, :general)
        end

        def self.brief(domain = :general)
          ([*BRIEFS[:general], *BRIEFS.fetch(domain.to_sym, [])]).uniq.join("\n- ").then do |text|
            "Quality framework:\n- #{text}"
          end
        end
      end
    end
  end
end
