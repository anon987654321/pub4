# frozen_string_literal: true

require "fileutils"
require "shellwords"

module Master
  module Voice
    # The sound under the session, rendered by STUDIO/dilla. Prerendered tracks from the cache play one after
    # another, never the same twice running, and a nice'd background render tops the cache up. Started at
    # boot (bard.bed.autostart) it is held for the whole session: the bard's task ending releases it, which
    # stops only a bed the bard started. With an empty cache it streams dilla live when `live` allows, and
    # otherwise waits for the first render. Every choice lives in voice.yml under bard.bed.
    module Bed
      module_function

      RENDER_POLL_S = 5

      # MASTER_BED=0 keeps the speakers quiet whatever voice.yml says: the test suite sets it.
      def start(config)
        return false if ENV["MASTER_BED"] == "0"
        return false unless config.is_a?(Hash) && config["enabled"] == true
        return true if running?

        FileUtils.mkdir_p(cache_dir(config))

        started = tracks(config).any? || config["live"] == false ? rotate(config) : launch(live_command(config))
        prerender(config)
        started
      end

      # At session start, when voice.yml says so (bard.bed.autostart): the bed is there from the first moment and
      # held until the session closes.
      def boot(config)
        return unless config.is_a?(Hash) && config["autostart"] == true

        @held = start(config)
        nil
      end

      def held? = @held == true

      # The bard's end of a task: a bed held since boot plays on.
      def release
        stop unless held?
      end

      def launch(argv)
        return false unless argv

        FileUtils.mkdir_p(workdir)
        options = { out: File::NULL, err: File::NULL, pgroup: true, chdir: workdir }

        @pid = Process.spawn(*argv, **Master::Io::ProcessSpawn.options(options))
        @waiter = Process.detach(@pid)
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

      # ::Random is Ruby's; inside Master a bare Random is Master::Random, a module with no new.
      def cached(config, random: ::Random.new) = tracks(config).sample(random:)

      def stop
        @stopping = true
        @held = false
        pid, @pid = @pid, nil
        signal(-pid, "TERM") if pid
      end

      def running? = (!@pid.nil? && signal(@pid, 0)) || (@rotation&.alive? == true)

      # A bed the bard started, as opposed to the ambient held since boot.
      def foreground? = !held? && running?

      # Plays the cached tracks in turn, a different one next, until stopped. An empty cache waits for a render.
      def rotate(config)
        @stopping = false

        @rotation = Thread.new do
          Thread.current.report_on_exception = false
          last = nil
          last = play_next(config, last) until @stopping
        end
        true
      end

      def play_next(config, last)
        track = next_track(config, last)
        return wait_for_render(config) unless track

        play_through(loop_command(config, track))
        prerender(config)
        track
      end

      def wait_for_render(config)
        prerender(config)
        sleep(RENDER_POLL_S)
        nil
      end

      def next_track(config, last)
        pool = tracks(config)
        (pool - [last]).sample || pool.first
      end

      def play_through(argv)
        launch(argv) ? @waiter.join : @stopping = true
      end

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

      def live_command(config, random: ::Random.new)
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
      def prerender(config, random: ::Random.new)
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
