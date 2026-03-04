# frozen_string_literal: true

%w[json yaml].each { |lib| require lib }

module Paths
  DATA_DIR = File.expand_path("../data", __dir__)
  module_function

  def data_file(name)
    File.join(DATA_DIR, name.to_s)
  end
end

module Hooks
  RULES_FILE = "rules.yml"
  REPORT_FILE = "report.json"

  class Runner
    ACTION_HANDLERS = {
      "enforce_rules" => :enforce_rules,
      "scan_violations" => :scan_violations
    }.freeze

    def initialize(event:, payload:, repository: nil)
      @event = event.to_s
      @payload = payload || {}
      @repository = repository
    end

    def dispatch
      action_name = @payload.fetch(:action, @payload.fetch("action", nil)).to_s
      return { ok: false, error: "missing_action" } unless action_name && !action_name.empty?

      handler = ACTION_HANDLERS.fetch(action_name, nil)
      return { ok: false, error: "unknown_action", action: action_name } unless handler

      execute_action(handler, build_context)
    end

    private

    def execute_action(handler, context)
      public_send(handler, context)
    end

    def build_context
      {
        event: @event,
        rule_set_name: @payload.fetch(:rule_set, @payload.fetch("rule_set", "default")),
        dry_run: @payload.fetch(:dry_run, @payload.fetch("dry_run", false)),
        repository: @repository
      }
    end

    def enforce_rules(context)
      rule_set = load_rule_set(context.fetch(:rule_set_name))
      return { ok: false, error: "rule_set_not_found", rule_set: context[:rule_set_name] } unless rule_set

      violations = collect_rule_violations(rule_set, context)
      report = build_report(rule_set: rule_set, violations: violations, context: context)

      context.fetch(:dry_run, false) ? report : persist_report(report)
    end

    def scan_violations(context)
      rule_set = load_rule_set(context.fetch(:rule_set_name))
      return { ok: false, error: "rule_set_not_found", rule_set: context[:rule_set_name] } unless rule_set

      violations = collect_rule_violations(rule_set, context)
      build_report(rule_set: rule_set, violations: violations, context: context)
    end

    def load_rule_set(rule_set_name)
      rules_path = Paths.data_file(RULES_FILE)
      return nil unless File.file?(rules_path)

      yaml = YAML.safe_load(File.read(rules_path), permitted_classes: [], aliases: false) || {}
      yaml.fetch(rule_set_name.to_s, nil)
    end

    def collect_rule_violations(rule_set, context)
      repository = context.fetch(:repository, nil)
      return [] unless repository

      if repository.respond_to?(:rule_violations)
        scope = repository.rule_violations
        scope = scope.includes(:rule) if scope.respond_to?(:includes)
        scope.to_a
      else
        Array(rule_set.fetch("violations", []))
      end
    end

    def build_report(rule_set:, violations:, context:)
      violation_count = violations.respond_to?(:size) ? violations.size : Array(violations).size

      {
        ok: true,
        event: context.fetch(:event),
        rule_set: context.fetch(:rule_set_name),
        violation_count: violation_count,
        violations: serialize_violations(violations)
      }
    end

    def serialize_violations(violations)
      Array(violations).map do |violation|
        if violation.respond_to?(:attributes)
          violation.attributes
        else
          violation
        end
      end
    end

    def persist_report(report)
      report_path = Paths.data_file(REPORT_FILE)
      json = JSON.generate(report)
      File.write(report_path, json)
      report.merge(saved_to: report_path)
    rescue Errno::EACCES, Errno::ENOENT => e
      report.merge(ok: false, error: "write_failed", message: e.message)
    end
  end
end