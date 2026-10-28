# frozen_string_literal: true

# Detect unwrapped council calls at the call site. Runtime validation is provided
# by the shared adapter, so this detector guards against bypassing that adapter.
Law.define(:INTER_MODEL_CONTRACT) do
  source "MASTER/data/inter_model.yml — machine-validated peer-model exchanges"
  detect { |line| line.match?(/@agent\.ask(?:_once)?\(\s*prompt\b/) }
  ask <<~'ASK'.strip
    Do every MASTER-to-model council turn use InterModelContract to construct a structured request envelope,
    attach a SHA-256 artifact reference, validate the returned JSON finding schema, and record a bounded metric
    without persisting raw model text? Invalid output must receive one structured rejection and one retry only.
  ASK
  practice "Treat other models as protocol peers: explicit authority, evidence, bounded artifacts, structured disagreement, and no reciprocal persona."
  fix "Wrap every council model request with InterModelContract and validate its returned structured findings before aggregation."
  bad "@agent.ask(prompt)"
  good "@agent.ask(request_prompt)"
end
