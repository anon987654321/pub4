# frozen_string_literal: true

module Master
  module Ground
    # CaMeL-style capability tag: wraps untrusted tool output (web_fetch, read_file of
    # external content) so privileged tool calls can refuse to act on tainted data — the
    # #1 defence against prompt injection (OWASP LLM01). Refs: Defeating Prompt Injections
    # by Design / CaMeL (arXiv:2503.18813).
    Tainted = Struct.new(:value, :source) do
      def tainted? = true
      def to_s = value.to_s
    end
  end
end
