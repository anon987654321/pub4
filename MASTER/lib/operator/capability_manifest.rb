# frozen_string_literal: true

module Operator
  # Read-only snapshot of the current agent process's execution capabilities.
  # Permission is not execution, and unprobed powers remain not_probed.
  class CapabilityManifest
    def initialize(root:)
      @root = File.expand_path(root)
    end

    def call
      {
        "schema" => 1,
        "capabilities" => {
          "repository_read" => observed(File.directory?(@root) && File.readable?(@root),
                                        "repository directory is readable"),
          "repository_write_permission" => {
            "status" => File.writable?(@root) ? "permission_observed" : "permission_denied",
            "evidence" => "directory permission only; no write was attempted",
          },
          "ruby_runtime" => {
            "status" => "available",
            "evidence" => "running Ruby #{RUBY_VERSION}",
          },
          "git_metadata" => observed(File.exist?(File.join(@root, ".git")),
                                     "repository metadata path exists"),
          "local_shell" => not_probed("no shell command was launched by this report"),
          "remote_shell" => not_probed("no remote connection was attempted"),
          "browser" => not_probed("no browser session was opened by this report"),
          "github_api" => not_probed("no GitHub API request was made by this process"),
          "test_execution" => not_probed("no test command was run by this report"),
        },
      }
    end

    private

    def observed(value, evidence)
      { "status" => value ? "available" : "unavailable", "evidence" => evidence }
    end

    def not_probed(reason)
      { "status" => "not_probed", "evidence" => reason }
    end
  end
end
