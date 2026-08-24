# frozen_string_literal: true

module Master
  module Ground
    module Tool
      # Tool::Contract — typed contract for every tool execution.
      # Issue #396 item 7: route all tool execution through typed contracts.
      #
      # Contracts define allowed inputs, expected output shape, permission tier,
      # retry policy, timeout, and side-effect classification. The validator
      # enforces these at the call site before any tool runs.
      module Contract
        # name: Symbol tool id; inputs: { key => :required | :optional }
        # output_shape: expected output keys (or :any); permission: :read | :write | :exec | :network
        # timeout_s: hard timeout (Integer); side_effects: :filesystem | :network | :git | :process | :none
        # category: :reach | :judge | :trace | :ground
        Contract = Data.define(
          :name,
          :inputs,
          :output_shape,
          :permission,
          :timeout_s,
          :max_retries,
          :side_effects,
          :category,
        )

        REGISTRY = {
          web_fetch: Contract.new(
            name: :web_fetch, inputs: { url: :required, headers: :optional },
            output_shape: [:body], permission: :network, timeout_s: 30, max_retries: 2,
            side_effects: [:network], category: :reach
          ),
          file_read: Contract.new(
            name: :file_read, inputs: { path: :required },
            output_shape: [:content], permission: :read, timeout_s: 5, max_retries: 0,
            side_effects: [:none], category: :reach
          ),
          file_write: Contract.new(
            name: :file_write, inputs: { path: :required, content: :required },
            output_shape: [:written], permission: :write, timeout_s: 10, max_retries: 0,
            side_effects: [:filesystem], category: :reach
          ),
          shell_exec: Contract.new(
            name: :shell_exec, inputs: { command: :required, cwd: :optional },
            output_shape: %i[stdout stderr exit_code], permission: :exec, timeout_s: 60,
            max_retries: 0, side_effects: %i[process filesystem], category: :reach
          ),
          git_op: Contract.new(
            name: :git_op, inputs: { op: :required, args: :optional },
            output_shape: [:output], permission: :exec, timeout_s: 30, max_retries: 1,
            side_effects: %i[git filesystem], category: :reach
          ),
          llm_call: Contract.new(
            name: :llm_call, inputs: { prompt: :required, model: :optional, system: :optional },
            output_shape: %i[text tokens], permission: :network, timeout_s: 120, max_retries: 2,
            side_effects: [:network], category: :ground
          ),
          scan: Contract.new(
            name: :scan, inputs: { path: :required, depth: :optional },
            output_shape: [:findings], permission: :read, timeout_s: 60, max_retries: 0,
            side_effects: [:none], category: :judge
          ),
          postpro: Contract.new(
            name: :postpro, inputs: { args: :optional },
            output_shape: %i[stdout stderr exit_code], permission: :exec, timeout_s: 600,
            max_retries: 0, side_effects: %i[process filesystem], category: :reach
          ),
          repligen: Contract.new(
            name: :repligen, inputs: { args: :optional },
            output_shape: %i[stdout stderr exit_code], permission: :network, timeout_s: 900,
            max_retries: 0, side_effects: %i[network process filesystem], category: :reach
          ),
        }.freeze

        module_function

        def find(name)
          REGISTRY[name.to_sym]
        end

        # Validate args against contract before execution.
        # Returns Result::Ok(contract) or Result::Err with violation details.
        # For shell_exec and git_op, runs injection_guard on command/args.
        def validate(name, args = {})
          contract = find(name)
          return Result.err("unknown tool: #{name}", category: :validation) unless contract

          missing = contract.inputs.select { |k, req| req == :required && !args.key?(k) }.keys
          return Result.err("#{name}: missing required inputs: #{missing.join(', ')}", category: :validation) if missing.any?

          if %i[shell_exec git_op].include?(name.to_sym)
            shell_input = args.fetch(:command) { Array(args[:args]).join(" ") }
            guard = Master::Review::Security::InjectionGuard.new(mode: :strict)
            check = guard.safe?(shell_input.to_s)
            return Result.err("#{name}: injection detected in input", category: :policy) unless check
          end

          Result.ok(contract)
        end

        def permitted_for?(name, permission_level)
          contract = find(name)
          return false unless contract
          permission_rank(contract.permission) <= permission_rank(permission_level)
        end

        def permission_rank(p)
          { read: 0, write: 1, network: 2, exec: 3 }.fetch(p.to_sym, 9)
        end
      end
    end
  end
end
