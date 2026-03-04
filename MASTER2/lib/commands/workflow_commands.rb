# frozen_string_literal: true

module Commands
  module WorkflowCommands
    DEFAULT_PER_PAGE = 50

    Result = Struct.new(:ok?, :message, :workflow, :errors, keyword_init: true)

    def manage_workflow(args)
      command, workflow_identifier, *command_args = parse_workflow_args(args)

      return Result.new(ok?: false, message: "Missing command") unless command
      return Result.new(ok?: false, message: "Missing workflow identifier") unless workflow_identifier

      workflow = find_workflow(workflow_identifier)
      return Result.new(ok?: false, message: "Workflow not found: #{workflow_identifier}") unless workflow

      dispatch_workflow_command(command, workflow, command_args)
    end

    private

    def parse_workflow_args(args)
      tokens = args.to_s.split.map(&:strip).reject(&:empty?)
      [tokens[0], tokens[1], *tokens[2..]]
    end

    def find_workflow(identifier)
      Workflow
        .includes(:steps, :owner)
        .find_by(id: identifier) || Workflow.find_by(slug: identifier)
    end

    def dispatch_workflow_command(command, workflow, command_args)
      case command
      when "scan"
        scan_workflow(workflow)
      when "enforce"
        enforce_workflow(workflow)
      when "reflow"
        reflow_workflow(workflow)
      when "build"
        build_workflow(workflow, command_args)
      else
        Result.new(ok?: false, message: "Unknown command: #{command}")
      end
    end

    def scan_workflow(workflow)
      issues = WorkflowScanner.new(workflow).scan
      Result.new(ok?: true, workflow: workflow, message: "Scan completed", errors: issues)
    end

    def enforce_workflow(workflow)
      enforcement = WorkflowEnforcer.new(workflow).enforce
      return Result.new(ok?: false, workflow: workflow, message: "Enforcement failed", errors: enforcement.errors) unless enforcement.success?

      Result.new(ok?: true, workflow: workflow, message: "Enforcement completed")
    end

    def reflow_workflow(workflow)
      reflow = WorkflowReflowService.new(workflow).reflow
      return Result.new(ok?: false, workflow: workflow, message: "Reflow failed", errors: reflow.errors) unless reflow.success?

      Result.new(ok?: true, workflow: workflow, message: "Reflow completed")
    end

    def build_workflow(workflow, command_args)
      blueprint_name = command_args.first
      return Result.new(ok?: false, workflow: workflow, message: "Missing blueprint name") unless blueprint_name

      build = WorkflowBuilder.new(workflow).build_from_blueprint(blueprint_name)
      return Result.new(ok?: false, workflow: workflow, message: "Build failed", errors: build.errors) unless build.success?

      Result.new(ok?: true, workflow: workflow, message: "Build completed")
    end
  end
end