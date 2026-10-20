# frozen_string_literal: true

require "fileutils"
require "shellwords"

module Master
  module Voice
    # The beat under the bard: STUDIO/dilla's own music, started with the first spoken line of a task and
    # stopped when the task ends. It is heard at once: a prerendered track from the cache plays on a loop,
    # and while the cache is short a nice'd background render adds tracks to it. With an empty cache the
    # first start streams dilla live (about six seconds to sound) and fills the cache for the next one.
    # Every choice lives in voice.yml under bard.bed: the progressions to draw from, the drums, the groove,
    # the players, the volume and the cache size. A different track is drawn per start.
    module Bed
      module_function

      def start(config)
        return false unless config.is_a?(Hash) && config["enabled"] == true
        return true if running?

        FileUtils.mkdir_p(cache_dir(config))

        started = (track = cached(config)) ? launch(loop_command(config, track)) : launch(live_command(config))
        prerender(config)
        started
      end

      def launch(argv)
        return false unless argv

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

      # dilla keeps its play state under ./out, so every dilla run starts from a scratch directory, never the repo.
      def workdir = File.join(Dir.home, ".master", "bed")

      def cache_dir(config) = File.expand_path(config.fetch("cache_dir", File.join(workdir, "cache")))

      def tracks(config) = Dir.glob(File.join(cache_dir(config), "*.wav")).select { |path| File.size?(path) }

      def cached(config, random: Random.new) = tracks(config).sample(random:)

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

      def tool(config)
        path = File.expand_path(File.join(Master::ROOT, "..", config.fetch("tool")))
        path if File.file?(path)
      end

      def live_command(config, random: Random.new)
        dilla = tool(config)
        return unless dilla

        args = Array(config["args"]).map(&:to_s) + pick_args(config, random)
        args += ["--player", player(config)] if config["player"]
        [RbConfig.ruby, dilla, *args]
      end

      def loop_command(config, track)
        line = format(config.fetch("loop_player"), volume: config.fetch("volume", 0.35), path: Shellwords.escape(track))
        line.shellsplit
      end

      def pick_args(config, random)
        pick = Array(config["progressions"]).sample(random:)
        (pick ? ["--progression", pick.to_s] : []) + ["--seed", random.rand(1..9999).to_s]
      end

      def player(config)
        format(config.fetch("player"), volume: config.fetch("volume", 0.35))
      end

      # One nice'd render at a time, until the cache holds `cache_target` tracks.
      def prerender(config, random: Random.new)
        return false if rendering? || tracks(config).size >= config.fetch("cache_target", 4)

        dilla = tool(config)
        return false unless dilla

        args = Array(config["render_args"]).map(&:to_s) + pick_args(config, random)

        out = File.join(cache_dir(config), "bed_#{random.rand(1..999_999)}.wav")
        spawn_render(["nice", "-n", "15", RbConfig.ruby, dilla, *args, "--out", out, "--replace"])
      end

      def spawn_render(argv)
        options = { out: File::NULL, err: File::NULL, pgroup: true, chdir: workdir }

        @render_pid = Process.spawn(*argv, **Master::Io::ProcessSpawn.options(options))
        Process.detach(@render_pid)
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Bed.spawn_render")
        @render_pid = nil
        false
      end

      def rendering? = !@render_pid.nil? && signal(@render_pid, 0)
    end
  end
end
