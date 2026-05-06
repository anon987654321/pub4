# frozen_string_literal: true

require "open3"
require "shellwords"

module Master
  module Tools
    # Repligen — drive the multimedia/repligen.rb Replicate.com CLI from MASTER.
    # Shells out so SQLite + net/http stay in their own process. REPLICATE_API_TOKEN
    # must be set in the parent env.
    class Repligen
      TIER        = :dangerous
      NAME        = "repligen".freeze
      DESCRIPTION = "Discover, search, and run Replicate.com models (image/video/music/upscale).".freeze
      TIMEOUT     = 1200
      SCRIPT_REL  = "../multimedia/repligen.rb".freeze
      ACTIONS     = %w[sync search stats].freeze

      def initialize(root:, governor:, event_bus: nil)
        @root     = root
        @governor = governor
        @bus      = event_bus
      end

      def call(action:, query: nil, limit: nil)
        action = action.to_s
        return Result.err("repligen: unknown action #{action}", category: :validation) unless ACTIONS.include?(action)
        return Result.err("repligen: REPLICATE_API_TOKEN not set", 
category: :validation) if action == "sync" && ENV["REPLICATE_API_TOKEN"].to_s.empty?

        script = File.expand_path(SCRIPT_REL, @root)
        return Result.err("repligen: script missing at #{script}", category: :infrastructure) unless File.exist?(script)

        argv = build_argv(action, query: query, limit: limit)
        perm = @governor.permit?(NAME, TIER, "repligen #{argv.join(' ')}")
        return perm if perm.err?

        @bus&.publish("tool:before", tool: NAME, action: action)

        out, err, status = Open3.capture3("ruby", script, *argv, chdir: File.dirname(script))

        @bus&.publish("tool:after", tool: NAME, exit: status.exitstatus)
        status.success? ? Result.ok(out.to_s.strip) :
                          Result.err("repligen: exit #{status.exitstatus} #{err.strip}", category: :provider_error)
      rescue StandardError => e
        Result.err("repligen: #{e.message}", category: :infrastructure)
      end

      private

      def build_argv(action, query:, limit:)
        case action
        when "sync"   then ["sync",   (limit || 100).to_i.clamp(1, 1000).to_s]
        when "search" then ["search", query.to_s]
        when "stats"  then ["stats"]
        end
      end
    end
  end
end
