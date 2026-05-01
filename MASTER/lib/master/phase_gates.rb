# frozen_string_literal: true

module Master
  PHASES = %w[discover analyze ideate design implement validate deliver idle].freeze

  class PhaseGates
    PHASE_STATE_PATH = "data/phase_state.yml".freeze

    GATES = {
      "discover"  => %w[problem_stated success_measurable],
      "analyze"   => %w[components_distinct dependencies_noted],
      "ideate"    => %w[alternatives_gte_3],
      "design"    => %w[interfaces_noted errors_noted],
      "implement" => %w[],
      "validate"  => %w[tests_noted],
      "deliver"   => %w[deployed_noted],
      "idle"      => %w[]
    }.freeze

    def initialize(root:, event_bus: nil)
      @root  = root
      @bus   = event_bus
      @state = load_state
    end

    def current = @state["phase"] || "idle"

    def advance!(to: nil)
      prev   = current
      target = to&.to_s || next_phase
      return Result.err("unknown phase: #{target}") unless PHASES.include?(target)

      unmet = unmet_gates(prev)
      if unmet.any?
        return Result.err("phase #{prev} gates unmet: #{unmet.join(",")} — override with /phase advance --force")
      end

      @state["phase"] = target
      @state["entered_at"] = Time.now.to_i
      persist
      @bus&.publish("phase:advanced", from: prev, to: target)
      Result.ok("phase: #{prev} -> #{target}")
    end

    def force!(phase)
      @state["phase"] = phase.to_s
      @state["entered_at"] = Time.now.to_i
      persist
      Result.ok("phase forced to #{phase}")
    end

    def meet_gate!(gate)
      @state["met_gates"] ||= []
      @state["met_gates"] |= [gate.to_s]
      persist
    end

    def status
      unmet = unmet_gates(current)
      met   = (@state["met_gates"] || []) & (GATES[current] || [])
      "phase=#{current} met=#{met.join(",")} unmet=#{unmet.join(",")}"
    end

    private

    def next_phase
      phase_index = PHASES.index(current) || 0
      PHASES[[phase_index + 1, PHASES.size - 1].min]
    end

    def unmet_gates(phase)
      required = GATES.fetch(phase, [])
      met = @state["met_gates"] || []
      required - met
    end

    def load_state
      path = File.join(@root, PHASE_STATE_PATH)
      return { "phase" => "idle", "met_gates" => [] } unless File.exist?(path)
      data = Master.load_yaml(path)
      data.is_a?(Hash) ? data : { "phase" => "idle", "met_gates" => [] }
    rescue StandardError
      { "phase" => "idle", "met_gates" => [] }
    end

    def persist
      path = File.join(@root, PHASE_STATE_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, YAML.dump(@state))
    end
  end
end
