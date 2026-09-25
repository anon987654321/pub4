# frozen_string_literal: true

require "etc"
require "json"
require "fileutils"

module Master
  module Device
    # Gives a new Termux install the face's ear without being asked: the
    # Termux:API recogniser, sox, ffmpeg and PulseAudio from pkg, whisper-cli,
    # and the multilingual base model, which is what a phone's memory holds.
    #
    # It runs on a background thread at boot, so the session opens at once,
    # and says what it does in the boot's own dmesg voice. A step already in
    # place is never run; the state file remembers failures, so a build that
    # fails waits an hour, then two, then four, and stops after five.
    class Setup
      Step = Data.define(:name, :says, :ready, :tries)

      STATE = MasterPaths.state("face_setup.json")
      LOG = MasterPaths.state("face_setup.log")
      PACKAGES = %w[termux-api sox ffmpeg pulseaudio].freeze
      # The four commands the ear runs; pkg names differ from two of them.
      PACKAGE_COMMANDS = %w[termux-speech-to-text sox ffmpeg parec].freeze
      BUILD_TOOLS = %w[git cmake clang make curl].freeze
      # whisper-cpp awaits review in termux-packages (PR 28329, open on
      # 2026-09-25), under x11-packages. Asking pkg first costs a few seconds
      # and starts working the day it merges; until then whisper.cpp builds
      # from source, statically, so the binary needs no library path.
      SOURCE = File.expand_path("~/.local/src/whisper.cpp")
      SOURCE_URL = "https://github.com/ggml-org/whisper.cpp"
      MODEL_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
      BACKOFF_S = 3_600
      MAX_FAILURES = 5

      # Starts the setup on a background thread when this is a phone missing
      # part of the ear. Never under test, and never when the operator said no.
      def self.start!(device: Device, env: ENV)
        return unless device.android?
        return if env["MASTER_IN_PROOF"] == "1" || env["MASTER_FACE_SETUP"] == "0"

        setup = new
        return if setup.ready?

        Thread.new { setup.run }.tap { |thread| thread.report_on_exception = false }
      end

      def initialize(env: ENV, which: ->(cmd) { Master::Voice::Playback.which(cmd) }, sh: nil, clock: -> { Time.now.to_i },
                     state_path: STATE, out: $stderr)
        @env = env
        @which = which
        @sh = sh || ->(argv) { spawn_logged(argv) }
        @clock = clock
        @state_path = state_path
        @out = out
      end

      def ready? = plan.all? { |step| step.ready.call }

      def plan
        [
          Step.new(:packages, "installing #{PACKAGES.join(" ")}",
                   -> { PACKAGE_COMMANDS.all? { |cmd| @which.call(cmd) } }, [[pkg(*PACKAGES)]]),
          Step.new(:whisper, "installing whisper-cli, from source if pkg lacks it",
                   -> { @which.call(Master::CLI::Face::Transcriber::WHISPER) }, [[pkg("x11-repo"), pkg("whisper-cpp")], build]),
          Step.new(:model, "fetching #{File.basename(model_path)}, about 142 MB",
                   -> { File.size?(model_path).to_i >= Master::CLI::Face::Transcriber::MIN_MODEL_BYTES }, [fetch]),
        ]
      end

      # Every step, each at most once, under a lock so two sessions starting
      # together do not run pkg twice.
      def run
        File.open("#{@state_path}.lock", File::RDWR | File::CREAT) do |lock|
          return unless lock.flock(File::LOCK_EX | File::LOCK_NB)

          plan.each { |step| advance(step) }
        end
      end

      # Where each step stands, for bin/doctor.
      def progress
        plan.map do |step|
          entry = state.fetch(step.name.to_s, {})
          stands = if step.ready.call then "ready"
                   elsif entry["failures"] then "failed #{entry["failures"]} of #{MAX_FAILURES}"
                   else "pending"
                   end
          "#{step.name} #{stands}"
        end.join(", ")
      end

      private

      def advance(step)
        entry = state.fetch(step.name.to_s, {})
        return settle(step, entry) if step.ready.call

        failures = entry.fetch("failures", 0)
        return say("#{step.name} stopped after #{failures} failures — delete #{@state_path} to try again") if failures >= MAX_FAILURES
        return say("#{step.name} waits until #{Time.at(entry["retry_at"]).strftime("%H:%M")}") if @clock.call < entry.fetch("retry_at", 0)

        say(step.says)
        worked = step.tries.any? { |commands| commands.all? { |argv| @sh.call(argv) } } && step.ready.call
        worked ? settle(step, entry, fresh: true) : failed(step, failures + 1)
      end

      # A step found in place is recorded silently; one this run finished says so.
      def settle(step, entry, fresh: false)
        return if entry["state"] == "done"

        say("#{step.name} ready") if fresh
        write(step.name.to_s => { "state" => "done", "at" => @clock.call })
      end

      def failed(step, failures)
        wait = BACKOFF_S * (2**(failures - 1))
        say("#{step.name} failed (#{failures} of #{MAX_FAILURES}), next try in #{wait / 3_600} h — #{LOG}")
        write(step.name.to_s => { "state" => "failed", "failures" => failures, "retry_at" => @clock.call + wait })
      end

      def pkg(*names) = ["pkg", "install", "-y", *names]

      def build
        build_dir = File.join(SOURCE, "build")
        [
          pkg(*BUILD_TOOLS),
          Dir.exist?(File.join(SOURCE, ".git")) ? ["git", "-C", SOURCE, "pull", "--ff-only"] : ["git", "clone", "--depth", "1", SOURCE_URL, SOURCE],
          ["cmake", "-S", SOURCE, "-B", build_dir, "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_SHARED_LIBS=OFF", "-DWHISPER_BUILD_TESTS=OFF"],
          ["cmake", "--build", build_dir, "--config", "Release", "-j", Etc.nprocessors.to_s, "--target", "whisper-cli"],
          ["install", "-m", "755", File.join(build_dir, "bin", "whisper-cli"), File.join(bin_dir, "whisper-cli")],
        ]
      end

      # curl -C - resumes a download a closed session cut short.
      def fetch
        part = "#{model_path}.part"
        [["mkdir", "-p", File.dirname(model_path)], ["curl", "-fL", "--retry", "3", "-C", "-", "-o", part, MODEL_URL], ["mv", part, model_path]]
      end

      def model_path = File.join(Master::CLI::Face::Transcriber::MODEL_DIR, Master::CLI::Face::Transcriber::INTERIM_MODEL)

      # Termux's own bin is on PATH; a Linux host without PREFIX gets ~/.local/bin.
      def bin_dir
        prefix = @env["PREFIX"].to_s
        prefix.empty? ? File.expand_path("~/.local/bin") : File.join(prefix, "bin")
      end

      def state
        JSON.parse(File.read(@state_path))
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end

      def write(entry)
        FileUtils.mkdir_p(File.dirname(@state_path))
        File.write(@state_path, JSON.pretty_generate(state.merge(entry)))
      end

      def say(line) = @out.puts("ear0: #{line}")

      # Output goes to the log, not the terminal the session is using, and
      # nothing can stop to ask a question.
      def spawn_logged(argv)
        FileUtils.mkdir_p(File.dirname(LOG))
        pid = Process.spawn({ "DEBIAN_FRONTEND" => "noninteractive" }, *argv, in: File::NULL, out: [LOG, "a"], err: [:child, :out])
        Process.wait2(pid).last.success?
      rescue SystemCallError
        false
      end
    end
  end
end
