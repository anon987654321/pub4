# frozen_string_literal: true

module Master
  module Now
    module CommandRegistry
      module HelpTopics
        ONE_LINERS = {
          "run" => "natural-language task via full pipeline",
          "scan" => "deep scan lib/ or path; --dry-run shows findings only",
          "self" => "self-scan MASTER lib/ with autofix",
          "fix" => "convergence loop; subcommands loop|preview|stop|--dry-run",
          "status" => "one-frame health panel",
          "resync" => "fetch, reset, bundle, restart; --dry-run previews",
          "tail" => "last N event-log lines; optional pattern",
          "help" => "one-liner per command; /help <cmd> for detail",
          "cost" => "session LLM spend total",
          "tokens" => "estimated session token count",
          "model" => "show or set active model; model list for catalog",
          "memory" => "list or search durable memory records",
          "orient" => "bootstrap doctrine by topic",
          "diag" => "runtime drives, breaker, logging snapshot"
        }.freeze

        DETAIL = {
          "scan" => [
            "scan: deep scan of lib/ or given path",
            "profiles: critical | solid | axioms prefix the path",
            "flags: --dry-run prints findings without mutation",
            "example: /scan lib/judge/scan/scanner.rb",
            "example: /scan critical lib/"
          ],
          "fix" => [
            "fix: run convergence loop on target directory",
            "fix loop: start background fix_loop",
            "fix stop: stop background fix_loop",
            "fix preview [path]: scan-only violation summary",
            "flags: --dry-run aliases preview",
            "example: /fix preview lib/loop/"
          ],
          "help" => [
            "help: list command one-liners",
            "help <command>: expanded usage for one command",
            "example: /help scan"
          ],
          "run" => [
            "run: preferred entry for natural-language tasks",
            "routes through intake → pipeline stages with intent inference",
            "example: /run scan face.js for NO_VAR violations"
          ]
        }.freeze

        module_function

        def summary
          ONE_LINERS.map { |cmd, line| "/#{cmd.ljust(12)} #{line}" }.join("\n")
        end

        def detail(command)
          key = command.to_s.delete_prefix("/").downcase
          lines = DETAIL[key]
          return "help: no detail for /#{key}. Try: #{DETAIL.keys.join(", ")}" unless lines
          lines.join("\n")
        end
      end
    end
  end
end