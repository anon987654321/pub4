# frozen_string_literal: true

# The constants and readers interaction_campaign_runner_test.rb shares with the tests split
# out of it to keep each file under its length ceiling.
module InteractionCampaignRunnerSources
  ROOT = File.expand_path("../../..", __dir__)
  MANIFEST = File.join(__dir__, "..", "interaction_campaign_400.json")
  Runner = Operator::InteractionCampaignRunner

  class Status
    def initialize(success, exitstatus)
      @success = success
      @exitstatus = exitstatus
    end

    def success? = @success
    attr_reader :exitstatus
  end

  def exercise_runtime_adapter(case_id:, source_path:, source:, adapter:, output:, expected_command:, expected_chdir_suffix:)
    Dir.mktmpdir("interaction-campaign-runtime-adapter") do |root|
      manifest_path = File.join(root, "RAILS", "test", "interaction_campaign_400.json")
      FileUtils.mkdir_p(File.dirname(manifest_path))
      manifest = JSON.parse(File.read(MANIFEST, encoding: "UTF-8"))
      row = manifest.fetch("cases").find { |item| item.fetch("id") == case_id }
      row["runtime_test"] = adapter
      surface = manifest.fetch("surfaces").find { |item| item.fetch("id") == row.fetch("surface_id") }
      surface.fetch("focused_test_paths") << source_path unless surface.fetch("focused_test_paths").include?(source_path)
      File.write(manifest_path, "#{JSON.pretty_generate(manifest)}\n")

      target = File.join(root, source_path)
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, source)
      calls = []
      executor = lambda do |command:, chdir:, timeout:|
        calls << { command:, chdir:, timeout: }
        [output, Status.new(true, 0)]
      end
      evidence_root = File.join(root, ".master", "interaction_campaign_runs")
      runner = Runner.new(
        case_ids: [case_id], root:, manifest_path:, evidence_root:,
        io: StringIO.new, executor:
      )

      assert_equal 0, runner.run
      assert_equal 1, calls.length
      assert_equal expected_command, calls.fetch(0).fetch(:command)
      assert calls.fetch(0).fetch(:chdir).end_with?(expected_chdir_suffix)
      result_path = Dir.glob(File.join(evidence_root, "**", "results.json")).first
      result = JSON.parse(File.read(result_path, encoding: "UTF-8")).fetch("results").fetch(0)
      assert_equal "PASS", result.fetch("status")
      assert_equal adapter.fetch("runner"), result.fetch("evidence").fetch("runner")
    end
  end
end
