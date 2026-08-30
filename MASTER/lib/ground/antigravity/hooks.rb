# frozen_string_literal: true

require "json"
require "open3"
require "timeout"
require_relative "discovery"

module Master
  module Ground
    module Antigravity
      # Hooks implements the Antigravity lifecycle hooks engine (hooks.json).
      # It executes commands at PreToolUse, PostToolUse, PreInvocation, PostInvocation,
      # and Stop lifecycle events with standard camelCase protojson stdin/stdout contract.
      class Hooks
        DEFAULT_TIMEOUT = 30

        attr_reader :discovery, :registered_hooks

        def initialize(discovery: Discovery.new)
          @discovery = discovery
          @registered_hooks = []
          load_hooks!
        end

        def load_hooks!
          @registered_hooks = []
          @discovery.hooks_files.each do |file_path|
            load_hook_file(file_path)
          end
        end

        def register_hook_data(hook_name, config, base_dir: @discovery.cwd)
          return unless config.is_a?(Hash) && config["enabled"] != false

          @registered_hooks << {
            name: hook_name,
            config:,
            base_dir:,
          }
        end

        # 1. PreToolUse: gates, blocks, audits, or overwrites tool executions
        def run_pre_tool_use(tool_name, args, context = {})
          payload = build_common_payload(context).merge(
            "stepIdx" => context.fetch(:step_idx, 1),
            "toolCall" => {
              "name" => tool_name.to_s,
              "args" => args || {},
            },
          )

          final_args = args ? args.dup : {}
          permission_overrides = []

          matching_handlers(:PreToolUse, tool_name).each do |handler, base_dir|
            res = execute_handler(handler, payload, base_dir:)
            next unless res.is_a?(Hash)

            decision = res["decision"].to_s
            reason = res["reason"].to_s

            if decision == "deny"
              return { allowed: false, decision: "deny", reason: (reason.empty? ? "Blocked by hook" : reason), args: final_args }
            elsif %w[ask force_ask].include?(decision)
              return { allowed: false, decision:, reason:, args: final_args }
            end

            Array(res["permissionOverrides"]).each { |p| permission_overrides << p }
            if res["overwrite"].is_a?(Hash)
              res["overwrite"].each { |k, v| final_args[k] = v }
            end
          end

          { allowed: true, decision: "allow", args: final_args, permission_overrides: }
        end

        # 2. PostToolUse: cleanup, auto-fixes, analysis
        def run_post_tool_use(tool_name, step_idx:, error: nil, context: {})
          payload = build_common_payload(context).merge(
            "stepIdx" => step_idx,
            "error" => error.to_s,
          )

          matching_handlers(:PostToolUse, tool_name).each do |handler, base_dir|
            execute_handler(handler, payload, base_dir:)
          end
          {}
        end

        # 3. PreInvocation: inject steps or context before model runs
        def run_pre_invocation(invocation_num:, initial_num_steps: 0, context: {})
          payload = build_common_payload(context).merge(
            "invocationNum" => invocation_num,
            "initialNumSteps" => initial_num_steps,
          )

          injected = []
          flat_handlers(:PreInvocation).each do |handler, base_dir|
            res = execute_handler(handler, payload, base_dir:)
            if res.is_a?(Hash) && res["injectSteps"].is_a?(Array)
              injected.concat(res["injectSteps"])
            end
          end

          { inject_steps: injected }
        end

        # 4. PostInvocation: inspect model outputs and force continuation if needed
        def run_post_invocation(invocation_num:, initial_num_steps: 0, context: {})
          payload = build_common_payload(context).merge(
            "invocationNum" => invocation_num,
            "initialNumSteps" => initial_num_steps,
          )

          injected = []
          termination_behavior = nil

          flat_handlers(:PostInvocation).each do |handler, base_dir|
            res = execute_handler(handler, payload, base_dir:)
            next unless res.is_a?(Hash)

            injected.concat(res["injectSteps"]) if res["injectSteps"].is_a?(Array)
            tb = res["terminationBehavior"].to_s
            termination_behavior = tb unless tb.empty?
          end

          { inject_steps: injected, termination_behavior: }
        end

        # 5. Stop: prevent loop termination if goals not met
        def run_stop(execution_num:, termination_reason: "model_stop", error: nil, fully_idle: true, context: {})
          payload = build_common_payload(context).merge(
            "executionNum" => execution_num,
            "terminationReason" => termination_reason,
            "error" => error.to_s,
            "fullyIdle" => fully_idle,
          )

          flat_handlers(:Stop).each do |handler, base_dir|
            res = execute_handler(handler, payload, base_dir:)
            if res.is_a?(Hash) && res["decision"] == "continue"
              return { decision: "continue", reason: res["reason"].to_s }
            end
          end

          { decision: "stop" }
        end

        private

        def load_hook_file(file_path)
          return unless File.file?(file_path)

          content = File.read(file_path, encoding: "UTF-8")
          data = JSON.parse(content)
          return unless data.is_a?(Hash)

          base_dir = File.dirname(file_path)
          data.each do |hook_name, hook_spec|
            register_hook_data(hook_name, hook_spec, base_dir:)
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.hooks.load", file_path:)
        end

        def matching_handlers(event_name, tool_name)
          handlers = []
          @registered_hooks.each do |hook|
            groups = Array(hook[:config][event_name.to_s])
            groups.each do |group|
              next unless group.is_a?(Hash)

              matcher = group["matcher"].to_s
              matcher_re = (matcher.empty? || matcher == "*") ? /.*/ : Regexp.new(matcher)
              next unless matcher_re.match?(tool_name.to_s)

              Array(group["hooks"]).each do |handler|
                handlers << [handler, hook[:base_dir]]
              end
            end
          end
          handlers
        end

        def flat_handlers(event_name)
          handlers = []
          @registered_hooks.each do |hook|
            list = Array(hook[:config][event_name.to_s])
            list.each do |handler|
              handlers << [handler, hook[:base_dir]] if handler.is_a?(Hash)
            end
          end
          handlers
        end

        def execute_handler(handler, payload, base_dir:)
          cmd = handler["command"].to_s
          return nil if cmd.empty?

          timeout_sec = Integer(handler.fetch("timeout", DEFAULT_TIMEOUT))
          expanded_cmd = cmd.sub(/\A~/, Dir.home)
          json_input = JSON.generate(payload)

          stdout_str, _stderr_str, status = Open3.popen3("sh", "-c", expanded_cmd, chdir: base_dir) do |stdin, stdout, stderr, wait_thr|
            stdin.write(json_input)
            stdin.close
            out_reader = Thread.new { stdout.read }
            err_reader = Thread.new { stderr.read }
            if wait_thr.join(timeout_sec)
              [out_reader.value, err_reader.value, wait_thr.value]
            else
              Process.kill("KILL", wait_thr.pid) rescue nil
              [stdout, stderr].each(&:close)
              out_reader.kill
              err_reader.kill
              raise Timeout::Error
            end
          end

          return nil unless status.success?

          trimmed = stdout_str.to_s.strip
          trimmed.empty? ? {} : JSON.parse(trimmed)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "antigravity.hooks.execute", cmd:)
          nil
        end

        def build_common_payload(context)
          {
            "conversationId" => context.fetch(:conversation_id, "master-session"),
            "workspacePaths" => Array(context.fetch(:workspace_paths, [@discovery.workspace_root])),
            "transcriptPath" => context.fetch(:transcript_path, File.expand_path("~/.gemini/antigravity-cli/transcript.jsonl")),
            "artifactDirectoryPath" => context.fetch(:artifact_directory_path, File.expand_path("~/.gemini/antigravity-cli/brain")),
            "modelName" => context.fetch(:model_name, "agy:auto"),
          }
        end
      end
    end
  end
end
