# frozen_string_literal: true

# Parked instruments. Off the boot path and out of the check ladder; the
# existing plugin host is the reader, so nothing new was built to list or
# revive these. status reports the park; run executes one instrument on demand.
require "open3"
require "rbconfig"
require "yaml"

module Master
  module Plugins
    class VideoRecordings < Master::Plugin::Base
      REVIVE_WHEN = "the face ships to a real visitor and needs regression capture"

      def call(action:, **rest)
        case action.to_s
        when "status" then status
        when "run"    then run(rest[:name].to_s, rest[:arg].to_s)
        else raise Master::Plugin::Error, "video_recordings: unknown action #{action}"
        end
      end

      private

      def status
        files = Dir.glob(File.join(__dir__, "**", "*")).count { |f| File.file?(f) }
        "parked: #{files} files; revive_when: #{REVIVE_WHEN}"
      end

      def run(name, arg)
        raise Master::Plugin::Error, "video_recordings: name an instrument to run" if name.empty?
        target = Dir.glob(File.join(__dir__, "**", name)).first
        raise Master::Plugin::Error, "video_recordings: no instrument #{name}" unless target
        out, st = Open3.capture2e(RbConfig.ruby, target, arg)
        [out, st.success? ? "ok" : "exit #{st.exitstatus}"].join("
")
      end
    end
  end
end
