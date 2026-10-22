# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module CLI
    class Pipeline
      # What a /fix run left for the next one on the same target: how it ended, the gates still red,
      # the files those gates named, and the command to run next. The next run reads it back, so its
      # gate-first worklist starts where this one stopped instead of rediscovering it.
      module Residual
        FILE = File.join(Master::ROOT, ".master", "fix_residual.json")

        module_function

        def path = ENV.fetch("MASTER_FIX_RESIDUAL", FILE)

        def write(target:, scorecard:, proof:, named:)
          hard, soft = proof ? proof.values_at(:hard, :soft) : [[], []]
          entry = { "at" => Time.now.utc.iso8601, "scorecard" => scorecard, "hard_red" => Array(hard),
                    "soft_red" => Array(soft), "named" => Array(named).sort,
                    "next" => next_command(target, hard) }
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, JSON.pretty_generate(all.merge(target.to_s => entry)))
          entry
        end

        def read(target) = all[target.to_s]

        def all
          File.file?(path) ? JSON.parse(File.read(path)) : {}
        rescue JSON::ParserError => e
          Master::Trace::Dmesg.status("fix0", "residual unreadable, starting fresh: #{e.message[0, 80]}")
          {}
        end

        # A hard gate left red is the blocker lane's work; otherwise a plain run continues.
        def next_command(target, hard)
          tree = File.basename(target.to_s)
          Array(hard).any? ? "MASTER/bin/fix-here #{tree} --blockers" : "MASTER/bin/fix-here #{tree}"
        end
      end
    end
  end
end
