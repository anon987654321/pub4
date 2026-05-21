# frozen_string_literal: true

module Master
  module Loop
  # Names the cybernetic shape of every loop in this directory.
  # Each entry maps a loop to its sensor (what it observes), setpoint
  # (where it aims), error metric (deviation it reduces), actuator
  # (what it changes), and feedback channel (event bus topic).
  #
  # The loops themselves stay where they are — this module is the
  # readable topology, queried by /explain and the runtime ecology view.
  module Cybernetics
    TOPOLOGY = {
      homeostat: {
        kind: :homeostasis,
        sensor: "event observations (llm_call, llm_failure, tool_call, idle_tick)",
        setpoint: "DRIVES[:setpoint] per drive (energy 0.7, error 0.0, novelty 0.5, fatigue 0.0, satiety 0.6)",
        error: "setpoint - state[drive]",
        actuator: "drive deltas + exponential decay back to setpoint",
        feedback: "homeostat:observe"
      },
      fix_loop: {
        kind: :negative_feedback,
        sensor: "scan_violations(files)",
        setpoint: "zero violations across two consecutive passes",
        error: "violations.size",
        actuator: "fast_pass (rubocop -A + AstFixer) then llm_pass per rule",
        feedback: "fix_loop:pass_start, fix_loop:clean, fix_loop:plateau, fix_loop:timeout"
      },
      rule_loop: {
        kind: :inner_loop,
        sensor: "scanner.scan(path, rules: [@rule])",
        setpoint: "zero violations for this single rule",
        error: "violations matching this rule",
        actuator: "council_fix (error tier) or request_fix (warning tier)",
        feedback: "rule_loop:pass, rule_loop:error"
      },
      watch_loop: {
        kind: :event_triggered,
        sensor: "filesystem change events under target paths",
        setpoint: "every change scanned within debounce window",
        error: "queued unscanned paths",
        actuator: "scan + autocommit via fix_loop",
        feedback: "watch_loop:scan_start, watch_loop:idle"
      },
      crdt_loop: {
        kind: :convergence,
        sensor: "remote LwwRegister proposals",
        setpoint: "eventual consistency across agents",
        error: "stale local state vs newer remote timestamp",
        actuator: "apply newer content to disk, broadcast via SSE",
        feedback: "crdt_loop:accepted, crdt_loop:merge"
      },
      heartbeat: {
        kind: :pacemaker,
        sensor: "wall clock + last-run-at journal",
        setpoint: "each job's cadence (hourly, 2-hourly, daily)",
        error: "now - last_run > cadence",
        actuator: "JOB_HANDLERS dispatch (prune_memory, check_models, self_test, snapshot)",
        feedback: "heartbeat:tick, heartbeat:job_done, heartbeat:error"
      },
      governor: {
        kind: :rate_governor,
        sensor: "tool invocation timestamps per tier",
        setpoint: "TIER_RATE_LIMITS (guarded 10/min, dangerous 3/min)",
        error: "calls within RATE_WINDOW vs limit",
        actuator: "Result.err :rate_limit; tool:rate_limited event",
        feedback: "tool:before, tool:rate_limited, tool:denied"
      }
    }.freeze

    def self.summary
      TOPOLOGY.map { |name, spec| "#{name} (#{spec[:kind]}): #{spec[:setpoint]}" }
    end

    def self.loops_by_kind(kind)
      TOPOLOGY.select { |_, spec| spec[:kind] == kind }.keys
    end
  end
  end
end
