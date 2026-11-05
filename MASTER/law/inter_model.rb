# frozen_string_literal: true

# Detect direct council calls that bypass the shared request/response adapter.
# The detector is deliberately limited to call sites whose argument is named
# prompt, a heredoc prompt, or a prompt: keyword. Calls using the adapter's
# outbound envelope are allowed; their argument is named outbound/request.
Law.define(:INTER_MODEL_CONTRACT) do
  path "MASTER/lib/review/council/"
  source "MASTER/data/inter_model.yml - machine-validated peer-model exchanges"
  detect do |line|
    call = line.match(/@agent\.ask(?:_once)?\s*\((.*)\z/)
    call && (
      call[1].match?(/\A\s*prompt\b/) ||
      call[1].match?(/\A\s*<<[-~]?\s*[A-Z_]\w*/) ||
      call[1].match?(/\bprompt\s*:/)
    )
  end
  ask <<~'ASK'.strip
    Does every MASTER-to-model council turn use InterModelContract to construct a structured request envelope,
    attach a SHA-256 artifact reference, validate the returned JSON finding schema, and record a bounded metric
    without persisting raw model text? Invalid output must receive one structured rejection and one retry only.
  ASK
  practice <<~'PRACTICE'.strip
    Treat other models as protocol peers: explicit authority, evidence, bounded artifacts, structured disagreement,
    and no reciprocal persona.
  PRACTICE
  fix <<~'FIX'.strip
    Wrap every council model request with InterModelContract and validate its returned structured findings
    before aggregation.
  FIX
  bad "@agent.ask(prompt)"
  good "@agent.ask(outbound)"
end
