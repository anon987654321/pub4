# frozen_string_literal: true

module Master
  module Ground
    # Research-derived operational thresholds and verification policy.
    module ResearchThresholds
      THRESHOLDS = {
        clone_similarity: 0.70,
        duplicate_min_tokens: 100,
        semantic_clone_f1_target: 0.90,
        api_timeout_s: 600,
        connect_timeout_s: 5,
        retry_attempts: 3,
        max_backoff_s: 20,
        backoff_base_s: 0.1,
        circuit_min_requests: 20,
        circuit_error_rate: 0.50,
        circuit_sleep_window_ms: 5_000,
        circuit_rolling_window_ms: 10_000,
        rate_limit_cooldown_s: 60,
        attention_sink_tokens: 4,
        prompt_compression_ratio: 20,
        rag_chunk_tokens: 512,
        rag_factoid_chunk_tokens: 256,
        rag_analytical_chunk_tokens: 1_024,
        rag_overlap: 0.15,
        self_consistency_samples: 7,
        semantic_entropy_samples: 5,
        ast_chunk_nodes: 175,
        diff_context_lines: 5,
        permission_order: %i[pre_tool_hook deny allow ask mode_check],
      }.freeze

      ENFORCEMENT_ORDER = %i[
        security_veto
        permission_authorization
        input_validation_normalization
        quality_style
        output_verification,
      ].freeze

      OUTPUT_POLICY = {
        edit_format: :unified_diff,
        avoid_line_numbers: true,
        prefer_function_level_edits: true,
        continue_on_finish_reason_length: true,
        preserve_system_message: true,
      }.freeze

      VERIFICATION_POLICY = {
        chain_of_verification: %i[baseline verification_questions independent_check final_revision],
        semantic_entropy: { samples: THRESHOLDS[:semantic_entropy_samples], cluster_by: :meaning },
        self_consistency: { samples: THRESHOLDS[:self_consistency_samples], vote: :majority },
        swe_bench_style: %i[fail_to_pass pass_to_pass regression],
      }.freeze

      def self.threshold(name) = THRESHOLDS.fetch(name.to_sym)

      def self.brief
        <<~TEXT.strip
          Evidence-based assistant policy:
          - duplication: 70% similarity, 100+ tokens, abstract on 3rd occurrence; avoid hasty abstractions.
          - resilience: 600s request timeout, 5s connect timeout, 2-3 retries,
            jittered exponential backoff capped at 20s, 50% circuit-breaker threshold.
          - context: keep 4 attention-sink tokens, use 512-token balanced RAG chunks
            with 10-20% overlap, compress up to 20x when needed.
          - verification: 5 semantic-entropy samples, 5-10 self-consistency paths,
            Chain-of-Verification before high-stakes claims.
          - output: unified diffs, no line-number dependence, function-level hunks,
            continue on truncation.
          - permissions: deny beats allow; security veto -> authorization ->
            normalization -> quality -> output verification.
        TEXT
      end
    end
  end
end
