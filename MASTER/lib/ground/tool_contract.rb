# frozen_string_literal: true

module Master
  module Ground
  # ToolContract — typed contract for every tool execution.
  # Issue #396 item 7: route all tool execution through typed contracts.
  #
  # Contracts define allowed inputs, expected output shape, permission tier,
  # retry policy, timeout, and side-effect classification. The validator
  # enforces these at the call site before any tool runs.
  module ToolContract
    Contract = Data.define(
      :name,          # Symbol — tool identifier
      :inputs,        # Hash { key => :required | :optional }
      :output_shape,  # Array of expected output keys (or :any)
      :permission,    # :read | :write | :exec | :network
      :timeout_s,     # Integer — hard timeout
      :max_retries,   # Integer
      :side_effects,  # Array of Symbols — :filesystem | :network | :git | :process | :none
      :category       # :reach | :judge | :trace | :ground
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
        output_shape: [:stdout, :stderr, :exit_code], permission: :exec, timeout_s: 60,
        max_retries: 0, side_effects: [:process, :filesystem], category: :reach
      ),
      git_op: Contract.new(
        name: :git_op, inputs: { op: :required, args: :optional },
        output_shape: [:output], permission: :exec, timeout_s: 30, max_retries: 1,
        side_effects: [:git, :filesystem], category: :reach
      ),
      llm_call: Contract.new(
        name: :llm_call, inputs: { prompt: :required, model: :optional, system: :optional },
        output_shape: [:text, :tokens], permission: :network, timeout_s: 120, max_retries: 2,
        side_effects: [:network], category: :ground
      ),
      scan: Contract.new(
        name: :scan, inputs: { path: :required, depth: :optional },
        output_shape: [:findings], permission: :read, timeout_s: 60, max_retries: 0,
        side_effects: [:none], category: :judge
      )
    }.freeze

    module_function

    def find(name)
      REGISTRY[name.to_sym]
    end

    # Validate args against contract before execution.
    # Returns Result::Ok(contract) or Result::Err with violation details.
    def validate(name, args = {})
      contract = find(name)
      return Result.err("unknown tool: #{name}", category: :validation) unless contract

      missing = contract.inputs.select { |k, req| req == :required && !args.key?(k) }.keys
      return Result.err("#{name}: missing required inputs: #{missing.join(', ')}", category: :validation) if missing.any?

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
