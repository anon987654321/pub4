# frozen_string_literal: true

module Operator
  # How a mapped campaign case becomes one exact test command, and how that
  # command's summary line is read back. Included by InteractionCampaignRunner,
  # whose campaign, @root and safe_repo_file these methods use.
  module InteractionCampaignAdapters
    def command_for(row, adapter)
      path = adapter.fetch("path").to_s
      name = adapter.fetch("name").to_s
      runner = adapter.fetch("runner", "rails_minitest").to_s
      return { error: "runtime test path must be repository-relative" } if path.start_with?("/") || path.split("/").include?("..")
      return { error: "runtime test name is invalid" } unless name.match?(/\Atest_[A-Za-z0-9_]+\z/)

      surface = campaign.fetch("surfaces").find { |item| item.fetch("id") == row.fetch("surface_id") }
      return { error: "runtime test surface is missing" } unless surface
      allowed = surface.fetch("focused_test_paths") + surface.fetch("evidence_paths")
      return { error: "runtime test path is not in the canonical surface evidence map" } unless allowed.include?(path)

      absolute = safe_repo_file(path)
      return { error: "runtime test file is missing, symlinked or outside the repository" } unless absolute

      source = File.read(absolute, encoding: "UTF-8")
      case runner
      when "rails_minitest"
        unless source.match?(/^\s*def\s+#{Regexp.escape(name)}(?:\s|\(|$)/)
          return { error: "runtime test method #{name} is not defined in #{path}" }
        end

        match = path.match(%r{\A(RAILS/[A-Za-z0-9_-]+|MASTER/web)/(.+)\z})
        return { error: "Rails runtime adapter must target an app-owned test path" } unless match

        app_root = File.join(@root, match[1])
        return { error: "runtime test app has no bin/rails" } unless File.file?(File.join(app_root, "bin", "rails"))

        relative_test = match[2]
        command = ["bin/rails", "test", relative_test, "--name", "\\A#{name}\\z"]
      when "ruby_minitest"
        unless source.match?(/^\s*def\s+#{Regexp.escape(name)}(?:\s|\(|$)/)
          return { error: "runtime test method #{name} is not defined in #{path}" }
        end

        match = path.match(/\AMASTER\/test\/(.+\.rb)\z/)
        return { error: "Ruby Minitest adapter must target MASTER/test" } unless match

        app_root = File.join(@root, "MASTER")
        relative_test = match[1]
        command = ["ruby", "-Itest", relative_test, "--name", "\\A#{name}\\z"]
      when "node_test"
        if path.match?(/\ARAILS\/test\/.+\.mjs\z/)
          app_root = File.join(@root, "RAILS")
          relative_test = path.delete_prefix("RAILS/")
        else
          match = path.match(%r{\A(RAILS/[A-Za-z0-9_-]+|MASTER/web)/(.+\.mjs)\z})
          return { error: "Node test adapter must target a RAILS app, MASTER/web or RAILS/test .mjs file" } unless match

          app_root = File.join(@root, match[1])
          relative_test = match[2]
        end
        if relative_test.to_s.empty?
          return { error: "Node test path is empty" }
        end
        unless relative_test.end_with?(".mjs")
          return { error: "Node test adapter must target an .mjs file" }
        end

        registration = /(?:test|it)\s*\(\s*["'`]#{Regexp.escape(name)}["'`]/
        return { error: "exact Node test #{name} is not registered in #{path}" } unless source.match?(registration)
        return { error: "Node adapter source does not expose an assertion" } unless source.match?(/\bassert(?:\.|\s*\()/)

        command = ["node", "--test", "--test-reporter=tap", "--test-name-pattern", "^#{Regexp.escape(name)}$", relative_test]
      else
        return { error: "unsupported runtime test runner #{runner}" }
      end

      {
        app_root:,
        test_path: absolute,
        command:,
        runner:
      }
    rescue KeyError => e
      { error: "runtime adapter is missing #{e.key}" }
    rescue StandardError => e
      { error: "runtime adapter validation failed: #{e.class}" }
    end

    def parse_summary(output, runner)
      if runner == "node_test"
        patterns = {
          runs: /(?:\A|\n)# tests (\d+)\s*(?:\r?\n|\z)/,
          passes: /(?:\A|\n)# pass (\d+)\s*(?:\r?\n|\z)/,
          failures: /(?:\A|\n)# fail (\d+)\s*(?:\r?\n|\z)/,
          skips: /(?:\A|\n)# skipped (\d+)\s*(?:\r?\n|\z)/
        }
        values = patterns.to_h do |key, pattern|
          match = output.to_s.match(pattern)
          [key, match && match[1].to_i]
        end
        return nil if values.values.any?(&:nil?)

        return values.merge(assertions: nil, errors: 0)
      end

      match = output.to_s.match(/(?:\A|\n)\s*(\d+) runs?, (\d+) assertions?, (\d+) failures?, (\d+) errors?(?:, (\d+) skips?)?/m)
      return nil unless match

      runs, assertions, failures, errors, skips = match.captures.map { |value| value.to_s.to_i }
      { runs:, assertions:, failures:, errors:, skips:, passes: nil }
    end
  end
end
