# frozen_string_literal: true

require "fileutils"
require "open3"
require "set"
require "yaml"

module Master
  module Ground
    PHASES = %w[discover analyze ideate design implement validate deliver idle].freeze

    class PhaseGates
      include AtomicWrite
      PHASE_STATE_PATH = "data/phase_state.yml".freeze
      REQUIRED_EDGE_CASES = %w[nil empty max unicode].freeze
      VAGUE_WORDS = /\b(it|thing|things|stuff|something|somehow)\b/i

      GATES = {
        "discover" => %w[no_vague_words audience_identified success_measurable],
        "analyze" => %w[components_distinct dependencies_acyclic],
        "ideate" => %w[count_gte_15 trade_offs_documented],
        "design" => %w[interfaces_explicit errors_documented],
        "implement" => %w[tests_pass zero_violations],
        "validate" => %w[zero_test_failures edge_cases_covered],
        "deliver" => %w[deployed monitoring_configured],
        "idle" => %w[],
      }.freeze

      def initialize(root:, event_bus: nil)
        @root = root
        @bus = event_bus
        @state = load_state
      end

      def current
        @state["phase"] || "idle"
      end

      def advance!(to: nil)
        prev = current
        target = to&.to_s || next_phase
        return Master::Result.err("unknown phase: #{target}") unless PHASES.include?(target)

        unmet = unmet_gates(prev)
        if unmet.any?
          return Master::Result.err(
            "phase blocked: #{prev} -> #{target}; unmet gates: #{unmet.join(", ")}"
          )
        end

        @state["phase"] = target
        @state["entered_at"] = Time.now.to_i
        persist
        @bus&.publish("phase:advanced", from: prev, to: target)
        Master::Result.ok("phase: #{prev} -> #{target}")
      end

      def force!(phase)
        return Master::Result.err("unknown phase: #{phase}") unless PHASES.include?(phase.to_s)

        @state["phase"] = phase.to_s
        @state["entered_at"] = Time.now.to_i
        persist
        Master::Result.ok("phase forced to #{phase}")
      end

      def meet_gate!(gate)
        @state["met_gates"] ||= []
        @state["met_gates"] |= [gate.to_s]
        persist
      end

      def status
        unmet = unmet_gates(current)
        met = met_gates(current)
        "phase=#{current} gates=#{(GATES[current] || []).join(",")} met=#{met.join(",")} unmet=#{unmet.join(",")}"
      end

      private

      def next_phase
        phase_index = PHASES.index(current) || 0
        PHASES[[phase_index + 1, PHASES.size - 1].min]
      end

      def unmet_gates(phase)
        required = GATES.fetch(phase, [])
        required.reject { |gate| gate_met?(gate) }
      end

      def met_gates(phase)
        GATES.fetch(phase, []).select { |gate| gate_met?(gate) }
      end

      def gate_met?(gate)
        manual_gate?(gate) || automatic_gate_met?(gate)
      end

      def manual_gate?(gate)
        Array(@state["met_gates"]).map(&:to_s).include?(gate.to_s)
      end

      def automatic_gate_met?(gate)
        case gate.to_s
        when "no_vague_words" then problem_statement? && !problem_statement.match?(VAGUE_WORDS)
        when "audience_identified" then present?(@state["audience"])
        when "success_measurable" then success_measurable?
        when "components_distinct" then components_distinct?
        when "dependencies_acyclic" then dependencies_acyclic?
        when "count_gte_15" then alternatives.size >= 15
        when "trade_offs_documented" then Array(@state["trade_offs"]).size >= 2
        when "interfaces_explicit" then documented_interfaces?
        when "errors_documented" then present?(@state["errors"]) || present?(@state["error_handling"])
        when "tests_pass" then truthy?(@state["tests_pass"]) || status_file_ok?(".master/last_test_status")
        when "zero_violations" then zero_count?(@state["violations"]) || zero_scan_file?
        when "zero_test_failures" then zero_count?(@state["test_failures"]) || truthy?(@state["tests_pass"])
        when "edge_cases_covered" then edge_cases_covered?
        when "deployed" then truthy?(@state["deployed"]) || master_service_running?
        when "monitoring_configured" then monitoring_configured?
        else false
        end
      end

      def problem_statement
        @state["problem_statement"].to_s.strip
      end

      def problem_statement?
        present?(problem_statement)
      end

      def success_measurable?
        criteria = @state["success_criteria"].to_s
        present?(criteria) && criteria.match?(/\d|zero|none|all|pass|green|ship|deploy/i)
      end

      def components_distinct?
        components = Array(@state["components"]).map { |component| component_value(component, "responsibility") }
        components.size >= 2 && components.all? { |value| present?(value) } && components.uniq.size == components.size
      end

      def dependencies_acyclic?
        deps = @state["dependencies"]
        return true if deps.nil? || deps == {}
        return false unless deps.is_a?(Hash)

        cyclic_nodes(deps.transform_keys(&:to_s)).empty?
      end

      def cyclic_nodes(graph)
        visiting = Set.new
        visited = Set.new
        cyclic = Set.new
        graph.each_key { |node| visit_dependency(node, graph:, visiting:, visited:, cyclic:) }
        cyclic
      end

      def visit_dependency(node, graph:, visiting:, visited:, cyclic:)
        return if visited.include?(node)
        if visiting.include?(node)
          cyclic << node
          return
        end

        visiting << node
        Array(graph[node]).map(&:to_s).each { |child| visit_dependency(child, graph:, visiting:, visited:, cyclic:) }
        visiting.delete(node)
        visited << node
      end

      def alternatives
        Array(@state["alternatives"])
      end

      def documented_interfaces?
        interfaces = Array(@state["interfaces"])
        interfaces.any? && interfaces.all? { |entry| present?(component_value(entry, "name")) && present?(component_value(entry, "contract")) }
      end

      def edge_cases_covered?
        covered = Array(@state["edge_cases"]).map(&:to_s)
        (REQUIRED_EDGE_CASES - covered).empty?
      end

      def monitoring_configured?
        truthy?(@state["monitoring_configured"]) ||
          File.exist?(File.join(@root, "data", "openbsd.yml")) &&
            File.read(File.join(@root, "data", "openbsd.yml")).include?("system_health_checks")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "PhaseGates.monitoring_configured?")
        false
      end

      def master_service_running?
        _, _, status = Master::Reach::Exec.capture3("/usr/sbin/rcctl", "check", "master")
        status.success?
      rescue Errno::ENOENT => e
        Master::Ground::Swallow.log(e, context: "PhaseGates.master_service_running?")
        false
      end

      def zero_scan_file?
        path = File.join(@root, ".master", "last_scan.yml")
        return false unless File.exist?(path)

        data = YAML.safe_load(File.read(path), aliases: true)
        zero_count?(data["violations"] || data[:violations])
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "PhaseGates.zero_scan_file?")
        false
      end

      def status_file_ok?(relative)
        path = File.join(@root, relative)
        File.exist?(path) && File.read(path).strip == "ok"
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "PhaseGates.status_file_ok?")
        false
      end

      def zero_count?(value)
        value.to_i.zero? if value.respond_to?(:to_i)
      end

      def truthy?(value)
        value == true || value.to_s == "true" || value.to_s == "ok"
      end

      def component_value(component, key)
        component.is_a?(Hash) ? component[key] || component[key.to_sym] : component
      end

      def present?(value)
        !value.nil? && !value.to_s.strip.empty?
      end

      def load_state
        path = File.join(@root, PHASE_STATE_PATH)
        return { "phase" => "idle", "met_gates" => [] } unless File.exist?(path)
        data = YAML.safe_load(File.read(path), aliases: true)
        data.is_a?(Hash) ? data : { "phase" => "idle", "met_gates" => [] }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "phase_gates.load_state")
        { "phase" => "idle", "met_gates" => [] }
      end

      def persist
        path = File.join(@root, PHASE_STATE_PATH)
        FileUtils.mkdir_p(File.dirname(path))
        write_atomic(path, @state.to_yaml)
      end
    end
  end
end
