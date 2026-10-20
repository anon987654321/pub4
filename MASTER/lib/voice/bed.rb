# frozen_string_literal: true

require "fileutils"

module Master
  module Voice
    # The beat under the bard: STUDIO/dilla's own --play stream, started with the first spoken line of a
    # task and stopped when the task ends. Every choice lives in voice.yml under bard.bed: the progressions
    # to draw from, the drums, the groove, the player and its volume. One progression is drawn per start, so
    # the bed is not the same song twice.
    module Bed
      module_function

      def start(config)
        return false unless config.is_a?(Hash) && config["enabled"] == true
        return true if running?

        argv = command(config)
        argv ? launch(argv) : false
      end

      # dilla keeps its play state under ./out, so the stream runs from a scratch directory, never the repo.
      def launch(argv)
        FileUtils.mkdir_p(workdir)

        options = { out: File::NULL, err: File::NULL, pgroup: true, chdir: workdir }
        @pid = Process.spawn(*argv, **Master::Io::ProcessSpawn.options(options))
        Process.detach(@pid)
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Bed.launch")
        @pid = nil
        false
      end

      def workdir = File.join(Dir.home, ".master", "bed")

      def stop
        pid, @pid = @pid, nil
        signal(-pid, "TERM") if pid
      end

      def running? = !@pid.nil? && signal(@pid, 0)

      def signal(pid, name)
        Process.kill(name, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM => e
        Master::Ground::Swallow.log(e, context: "Voice::Bed.signal")
        false
      end

      def command(config, random: Random.new)
        tool = File.join(Master::ROOT, "..", config.fetch("tool"))
        return unless File.file?(tool)

        args = Array(config["args"]).map(&:to_s)
        pick = Array(config["progressions"]).sample(random:)
        args += ["--progression", pick.to_s] if pick
        args += ["--seed", random.rand(1..9999).to_s]
        args += ["--player", player(config)] if config["player"]
        [RbConfig.ruby, File.expand_path(tool), *args]
      end

      def player(config)
        format(config.fetch("player"), volume: config.fetch("volume", 0.35))
      end
    end
  end
end
