# frozen_string_literal: true

# Parked instruments. Off the boot path and out of the check ladder; the
# existing plugin host is the reader, so nothing new was built to list or
# revive these. status reports the park; run executes one instrument on demand.
require "open3"
require "rbconfig"
require "yaml"

module Master
  module Plugins
    class DesignCalibration < Master::Plugin::Base
      REVIVE_WHEN = "the layout campaign (P3-P5) restarts with traffic to calibrate against"

      def call(action:, **rest)
        case action.to_s
        when "status" then status
        when "run"    then run(rest[:name].to_s, rest[:arg].to_s)
        else raise Master::Plugin::Error, "design_calibration: unknown action #{action}"
        end
      end

      private

      def status
        files = Dir.glob(File.join(__dir__, "**", "*")).count { |f| File.file?(f) }
        "parked: #{files} files; revive_when: #{REVIVE_WHEN}"
      end

      def run(name, arg)
        raise Master::Plugin::Error, "design_calibration: name an instrument to run" if name.empty?
        target = Dir.glob(File.join(__dir__, "**", name)).first
        raise Master::Plugin::Error, "design_calibration: no instrument #{name}" unless target
        out, st = Open3.capture2e(RbConfig.ruby, target, arg)
        [out, st.success? ? "ok" : "exit #{st.exitstatus}"].join("
")
      end
    end
  end
end
