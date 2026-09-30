# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "socket"
require "time"

module Master
  module Ops
    # Keeps the single vm23 control-plane checkout converged with origin/main and
    # deploys every accepted main commit to the full fleet.
    #
    # This is deliberately a thread inside the one MASTER process. screen(1)
    # owns terminal persistence; MASTER owns process exclusivity and repository
    # convergence. A second MASTER process must never be started to do the same
    # work.
    class ControlPlane
      include Master::Io::AtomicWrite

      DEFAULT_INTERVAL = 30
      DEFAULT_DEPLOY = File.join("OPENBSD", "bin", "vps-deploy").freeze

      def self.start!(root: Master::ROOT, interval: nil, out: $stderr)
        new(root:, interval:, out:).start!
      end

      def initialize(root:, interval:, out:)
        @root = File.expand_path(root)
        @repo = File.expand_path("..", @root)
        @state_path = File.join(@root, ".master", "control_plane.json")
        @deploy = File.join(@repo, DEFAULT_DEPLOY)
        @interval = [interval.to_i, 5].max if interval
        @interval ||= DEFAULT_INTERVAL
        @out = out
        @stop = false
        @thread = nil
        @last_report = nil
      end

      def start!
        return self if @thread&.alive?

        @thread = Thread.new do
          Thread.current.report_on_exception = false
          run
        end
        self
      end

      def stop!
        @stop = true
        @thread&.join(2)
        @thread = nil
        self
      end

      def run
        until @stop
          cycle
          sleep_interruptibly(@interval)
        end
      rescue StandardError => e
        report("control0: stopped — #{e.class}: #{e.message}")
      end

      def cycle
        return report("control0: waiting — #{LoopOwner.active.fetch("loop", "loop")} owns the execution slot") if LoopOwner.active
        return report("control0: waiting — working tree is dirty") unless clean?

        fetch!
        synchronize_refs!
        deploy_if_needed!
      rescue CommandError => e
        report("control0: failed — #{e.message}")
      end

      private

      class CommandError < StandardError
        attr_reader :command, :output

        def initialize(command, output)
          @command = command
          @output = output
          super("#{command.join(" ")}: #{output.to_s.strip[0, 240]}")
        end
      end

      def clean?
        result = command("git", "-C", @repo, "status", "--porcelain")
        result[:status].success? && result[:stdout].strip.empty?
      end

      def fetch!
        result = command("git", "-C", @repo, "fetch", "--prune", "origin", "main")
        raise CommandError.new(["git", "fetch", "origin", "main"], result[:stderr]) unless result[:status].success?
      end

      def synchronize_refs!
        branch = text_command("git", "-C", @repo, "branch", "--show-current")
        unless branch == "main"
          raise CommandError.new(["git", "branch", "--show-current"], "vm23 control plane requires the main branch; current=#{branch.inspect}")
        end

        head = text_command("git", "-C", @repo, "rev-parse", "HEAD")
        remote = text_command("git", "-C", @repo, "rev-parse", "origin/main")
        return if head == remote

        if ancestor?(head, remote)
          result = command("git", "-C", @repo, "pull", "--ff-only", "origin", "main")
          raise CommandError.new(["git", "pull", "--ff-only", "origin", "main"], result[:stderr]) unless result[:status].success?
          report("control0: synced <- origin/main #{short(remote)}")
        elsif ancestor?(remote, head)
          result = command("git", "-C", @repo, "push", "origin", "main")
          raise CommandError.new(["git", "push", "origin", "main"], result[:stderr]) unless result[:status].success?
          report("control0: synced -> origin/main #{short(head)}")
        else
          raise CommandError.new(["git", "sync", "main"], "main and origin/main have diverged")
        end
      end

      def deploy_if_needed!
        head = text_command("git", "-C", @repo, "rev-parse", "HEAD")
        state = load_state
        return if state["deployed_sha"] == head

        return report("control0: waiting — loop slot active") if LoopOwner.active

        result = command("zsh", @deploy, "all")
        unless result[:status].success?
          save_state(head, "failed")
          raise CommandError.new(["zsh", @deploy, "all"], result[:stdout].to_s + result[:stderr].to_s)
        end

        save_state(head, "ok")
        report("control0: deployed #{short(head)} -> master brgen amber bsdports")
      end

      def ancestor?(older, newer)
        result = command("git", "-C", @repo, "merge-base", "--is-ancestor", older, newer)
        result[:status].success?
      end

      def text_command(*argv)
        result = command(*argv)
        raise CommandError.new(argv, result[:stderr]) unless result[:status].success?

        result[:stdout].strip
      end

      def command(*argv)
        stdout, stderr, status = Open3.capture3(*argv, chdir: @repo)
        { stdout:, stderr:, status: }
      end

      def load_state
        JSON.parse(File.read(@state_path))
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end

      def save_state(sha, status)
        dir = File.dirname(@state_path)
        FileUtils.mkdir_p(dir)
        payload = JSON.pretty_generate(
          "pid" => Process.pid,
          "host" => Socket.gethostname,
          "sha" => sha,
          "status" => status,
          "deployed_sha" => status == "ok" ? sha : load_state["deployed_sha"],
          "at" => Time.now.utc.iso8601
        )
        write_atomic(@state_path, payload + "\n", fsync: true, fsync_dir: true, mode: 0o600)
      end

      def short(sha)
        sha[0, 12]
      end

      def report(message)
        return if message == @last_report
        @last_report = message
        @out.puts(message)
      end

      def sleep_interruptibly(seconds)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        loop do
          break if @stop
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if remaining <= 0
          sleep([remaining, 1].min)
        end
      end
    end
  end
end
