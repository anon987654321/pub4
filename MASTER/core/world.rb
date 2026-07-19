# frozen_string_literal: true

require "fileutils"
require "open3"
require "securerandom"
require "timeout"
require "time"

module Master::Core
  # World — the only thing that touches the outside. Each verb is one handler;
  # the set is closed (Master::Core::VERBS), so the blast radius of the agent is the
  # surface of this file and nothing else. The Constitution has already admitted
  # whatever arrives here, so handlers do the IO plainly — their only added duty
  # is crash-safety (writes are atomic) and honest reporting. Reversing a whole
  # effect is the Fold's job via #checkpoint/#rollback, so handlers keep no
  # second, per-write backup of their own.
  #
  # This is where the old reach/ (git, web, fs), ops/, and tools/ collapse to.
  class World
    EXEC_TIMEOUT = 120  # seconds — max time for any subprocess call

    def initialize(root:, ask: nil, critique_runner: nil)
      @root = File.expand_path(root)
      @ask = ask
      @critique_runner = critique_runner
    end

    def verbs = Master::Core::VERBS

    def perform(effect)
      send("do_#{effect.verb}", **effect.args)
    rescue StandardError => e
      Observation.no("#{e.class}: #{e.message}")
    end

    def checkpoint
      {
        id: SecureRandom.hex(8),
        patch: worktree_patch,
      }
    end

    def rollback(checkpoint)
      return Observation.ok("rollback: clean #{checkpoint[:id]}") if checkpoint[:patch].to_s.empty?

      if git_has_head?
        git_capture("reset", "--hard", "HEAD")
        apply_patch(checkpoint[:patch])
      else
        apply_patch_reverse(checkpoint[:patch])
      end
      Observation.ok("rolled back tracked changes #{checkpoint[:id]}")
    rescue StandardError => e
      Observation.no("rollback failed: #{e.class}: #{e.message}")
    end

    private

    def do_read(path:, **)
      Observation.ok(File.read(within(path), encoding: "UTF-8").scrub)
    end

    def do_write(path:, content:, **)
      abs = within(path)
      FileUtils.mkdir_p(File.dirname(abs))
      write_atomic(abs, content)
      Observation.ok("wrote #{path} (#{content.bytesize}b)")
    end

    def do_exec(argv:, timeout: 60, env: {}, **)
      raise ArgumentError, "argv must be an array" unless argv.is_a?(Array)
      raise ArgumentError, "argv cannot be empty" if argv.empty?
      raise ArgumentError, "argv entries must be strings" unless argv.all? { |arg| arg.is_a?(String) }

      out = nil
      status = nil
      Timeout.timeout(Integer(timeout)) do
        out, status = Open3.capture2e(env.transform_keys(&:to_s), *argv, chdir: @root)
      end
      status.success? ? Observation.ok(out.strip) : Observation.no(out.strip)
    end

    def do_git(operation:, paths: [], message: nil, **)
      case operation.to_sym
      when :diff then Observation.ok(git_capture("diff"))
      when :stage then Observation.ok(git_capture("add", "--", *Array(paths)))
      when :commit then Observation.ok(git_capture("commit", "-m", message.to_s))
      else Observation.no("unknown git operation: #{operation}")
      end
    end

    def do_ask(prompt:, options: nil, **)
      return Observation.no("no surface to ask") unless @ask

      Observation.ok(@ask.call(prompt:, options:))
    end

    def do_note(**) = Observation.ok # the Memory keeps the note; nothing to do here

    def do_critique(scope: "diff", **)
      return Observation.no("critique: council runner unavailable") unless @critique_runner

      result = @critique_runner.call(root: @root, scope: scope.to_s)
      result.ok? ? Observation.ok(result.value!.to_s) : Observation.no(result.message.to_s)
    rescue StandardError => e
      Observation.no("critique: #{e.class}: #{e.message}")
    end

    # Paths are sandboxed to root; nothing escapes the workspace.
    def within(path)
      abs = File.expand_path(path, @root)
      raise "path escapes workspace: #{path}" unless abs == @root || abs.start_with?(@root + File::SEPARATOR)

      abs
    end

    # Write via tmp+rename: an OOM kill or crash mid-write can never leave a
    # half-written file, since rename is atomic on a POSIX filesystem. The tmp
    # sits beside the target so the rename stays on one device.
    def write_atomic(abs, content)
      tmp = "#{abs}.tmp.#{Process.pid}.#{SecureRandom.hex(4)}"
      File.write(tmp, content)
      File.rename(tmp, abs)
    rescue StandardError
      File.delete(tmp) if tmp && File.exist?(tmp)
      raise
    end

    def git_repo?
      _, status = bounded_capture2e("git", "-C", @root, "rev-parse", "--is-inside-work-tree")
      status.success?
    end

    def git_has_head?
      _, status = bounded_capture2e("git", "-C", @root, "rev-parse", "--verify", "HEAD")
      status.success?
    end

    # A workspace need not be a git repo. When it isn't, there is nothing to
    # capture and rollback becomes a clean no-op, so the fold still runs.
    def worktree_patch
      return "" unless git_repo?

      if git_has_head?
        git_capture("diff", "HEAD", "--binary", raw: true)
      else
        git_capture("diff", "--binary", raw: true)
      end
    end

    def git_capture(*args, raw: false)
      out, status = bounded_capture2e("git", "-C", @root, *args)
      raise out.strip unless status.success?

      raw ? out : out.strip
    end

    def apply_patch(patch)
      out, status = bounded_capture2e("git", "-C", @root, "apply", "--binary", "-", stdin_data: patch)
      raise out.strip unless status.success?
    end

    private

    # Bounded subprocess call with hard timeout (prevents wedged processes).
    # This replaces raw Open3 calls to enforce the ROBUSTNESS constraint in core.
    def bounded_capture2e(*cmd, stdin_data: nil)
      out = err = nil
      status = nil
      timeout_sec = Integer(ENV.fetch("MASTER_EXEC_TIMEOUT", EXEC_TIMEOUT))

      Timeout.timeout(timeout_sec) do
        out, err, status = Open3.capture3(*cmd, stdin_data:)
        out = "#{out}#{err}" if err && !err.empty?
      end

      [out, status]
    rescue Timeout::Error => e
      [("TIMEOUT after #{timeout_sec}s: #{cmd.first}"), nil]
    end

    def apply_patch_reverse(patch)
      out, status = Open3.capture2e("git", "-C", @root, "apply", "--reverse", "--binary", "-", stdin_data: patch)
      raise out.strip unless status.success?
    end

    def self.shell_git(root, operation, message = nil)
      args = operation == "commit" ? ["commit", "-m", message.to_s] : operation.split
      out, _ = Open3.capture2e("git", "-C", root, *args)
      out.strip
    end
  end
end
