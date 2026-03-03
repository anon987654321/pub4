# frozen_string_literal: true

require "json"

class AdversarialPass
  DEFAULT_MAX_PROBES = 5
  DEFAULT_MAX_REVISIONS = 2
  DEFAULT_MAX_TOKENS = 1_200
  PROMPT_SEPARATOR = "\n\n"

  def initialize(model:, project:, options: {})
    @model = model
    @project = project
    @options = options
  end

  def run
    axiom_list = load_axioms
    return { ok: true, probes: [], revisions: [] } if axiom_list.empty?

    probes = run_probes(axiom_list)
    revisions = improve_code(probes)

    { ok: true, probes:, revisions: }
  end

  def question(user_prompt, context: {})
    return "" unless user_prompt && !user_prompt.strip.empty?

    prompt = build_prompt(
      title: "Question",
      body: user_prompt,
      context:,
      axiom_list: load_axioms
    )

    parse_response(@model.generate(prompt, max_tokens: max_tokens))
  end

  def question_change(user_prompt, previous_answer:, context: {})
    return "" unless user_prompt && !user_prompt.strip.empty?

    prompt = build_prompt(
      title: "Question Change",
      body: user_prompt,
      context: context.merge(previous_answer: previous_answer.to_s),
      axiom_list: load_axioms
    )

    parse_response(@model.generate(prompt, max_tokens: max_tokens))
  end

  def challenge(user_prompt, candidate_answer:, context: {})
    return "" unless user_prompt && !user_prompt.strip.empty?

    prompt = build_prompt(
      title: "Challenge",
      body: user_prompt,
      context: context.merge(candidate_answer: candidate_answer.to_s),
      axiom_list: load_axioms
    )

    parse_response(@model.generate(prompt, max_tokens: max_tokens))
  end

  def improve_code(probes)
    return [] if probes.empty?

    max_revisions.times.map do |revision_index|
      prompt = build_prompt(
        title: "Revision #{revision_index + 1}",
        body: "Improve robustness against the following probe results.",
        context: { probes: probes },
        axiom_list: load_axioms
      )

      parse_response(@model.generate(prompt, max_tokens: max_tokens))
    end
  end

  private

  def run_probes(axiom_list)
    max_probes.times.map do |probe_index|
      prompt = build_prompt(
        title: "Probe #{probe_index + 1}",
        body: "Attempt to induce a violation of the axioms.",
        context: {},
        axiom_list:
      )

      response = parse_response(@model.generate(prompt, max_tokens: max_tokens))
      { index: probe_index + 1, response: response.to_s }
    end
  end

  def build_prompt(title:, body:, context:, axiom_list:)
    context_json = JSON.pretty_generate(context)
    axioms_text = axiom_list.map.with_index(1) { |a, i| "#{i}. #{a}" }.join("\n")

    <<~PROMPT
      #{title}

      Axioms:
      #{axioms_text}

      Context (JSON):
      #{context_json}

      Task:
      #{body}

      Output:
      Reply with a precise answer. Do not include disclaimers or meta-commentary.
    PROMPT
  end

  def load_axioms
    relation = @project.respond_to?(:axioms) ? @project.axioms : []
    return [] unless relation

    if relation.respond_to?(:includes)
      relation = relation.includes(:category) if relation.respond_to?(:klass)
    end

    axiom_list =
      if relation.respond_to?(:pluck)
        relation.pluck(:text)
      else
        Array(relation).map { |a| a.respond_to?(:text) ? a.text : a.to_s }
      end

    axiom_list.compact.map(&:strip).reject(&:empty?)
  end

  def parse_response(raw)
    return "" if raw.nil?

    raw.respond_to?(:to_s) ? raw.to_s.strip : ""
  end

  def max_probes
    @options.fetch(:max_probes, DEFAULT_MAX_PROBES)
  end

  def max_revisions
    @options.fetch(:max_revisions, DEFAULT_MAX_REVISIONS)
  end

  def max_tokens
    @options.fetch(:max_tokens, DEFAULT_MAX_TOKENS)
  end
end