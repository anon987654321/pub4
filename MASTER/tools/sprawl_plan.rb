# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "../lib/operator/sprawl_census"
require_relative "../lib/trace/dmesg"

module Operator
  module SprawlPlan
    ROOT = File.expand_path("../..", __dir__)
    OUT = File.join(ROOT, ".master", "sprawl_plan.yml")
    module_function

    def run(write: false, root: ROOT)
      census = SprawlCensus
      rows = []
      census.lone_dirs.each { |path| rows << proposal("namespace", path, "Review whether the directory buys a real namespace; flatten only when the constant and loader contract remain intact.") }
      census.stutter.each { |path| rows << proposal("stutter", path, "Rename or relocate so the concept is named once; preserve Zeitwerk entry points.") }
      census.vague_names.each { |path| rows << proposal("vague", path, "Replace the vague basename with the concrete role it serves; move consumers with the rename.") }

      current = {
        version: 1,
        generated_at: Time.now.utc.iso8601,
        policy: "PRESERVE_THEN_IMPROVE_NEVER_BREAK",
        mutates_source: false,
        candidates: rows.sort_by { |row| [row[:kind], row[:path]] },
      }

      Master::Trace::Dmesg.status("sprawl0", "#{rows.size} structural candidate(s) in plan")
      return current unless write

      FileUtils.mkdir_p(File.dirname(OUT))
      File.write(OUT, current.to_yaml)
      current
    rescue StandardError => e
      Master::Trace::Dmesg.status("sprawl0", "plan unavailable, #{e.class}: #{e.message}")
      raise
    end

    def proposal(kind, path, instruction)
      { kind:, path: path.sub("#{ROOT}/", ""), instruction: }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "time"
  Operator::SprawlPlan.run(write: ARGV.include?("--write"))
  exit 0
end
