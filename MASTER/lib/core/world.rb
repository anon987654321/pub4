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
    TERM_GRACE = 2      # seconds a killed child gets to exit on TERM before KILL

    # A subprocess killed by the timeout never exited, so there is no
    # Process::Status to report. Every caller of bounded_capture2e asks
    # `.success?`, so handing back nil turned a wedged git into a
    # NoMethodError raised from inside the fold — the one place that has to
    # stay standing when the outside world misbehaves. This stands in for the
    # missing status: not successful, no exit code.
    TimedOutStatus = Class.new do
      def success? = false
      def exitstatus = nil
      def to_s = "timed out"
    end
    TIMED_OUT = TimedOutStatus.new.freeze

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

    # Undo one failed effect — and only what that effect touched.
    #
    # The Fold takes a checkpoint immediately before each effect and rolls back
    # if that single effect errored, so the blast radius that is CORRECT here is
    # one effect's worth. What this did instead was `git reset --hard HEAD`,
    # which discards every uncommitted change in the working tree, and then
    # re-applied the checkpoint patch — a patch of tracked modifications as they
    # stood a moment earlier.
    #
    # In this repo that is destructive. The checkout is shared: other sessions
    # and a human edit it concurrently, and CLAUDE.md exists because that has
    # already cost real work. Anything another session changed between the
    # checkpoint and the failure was outside the patch and gone, and
    # anything they had staged lost its staged state either way. Undoing one
    # failed write by discarding everyone's uncommitted work is a worse outcome
    # than the write.
    #
    # So: a write is undone at its own path, which is known exactly. Anything
    # else has an unknown blast radius, and for those the honest answer is to say
    # the effect was not rolled back rather than to guess with `reset --hard`.
    # PRESERVE_FIRST and SURFACE_ERRORS_FIRST are both soul.yml code_rules; a
    # loud un-undone exec obeys them, a silent tree-wide reset obeys neither.
    def rollback(checkpoint, effect = nil)
      path = rollback_path(effect)

      # No path to scope to. An empty checkpoint means there was nothing to undo
      # in the first place; anything else is an effect whose reach is unknown.
      unless path
        return Observation.ok("rollback: clean #{checkpoint[:id]}") if checkpoint[:patch].to_s.empty?

        return Observation.no("rollback skipped #{checkpoint[:id]}: no path to scope to, and a tree-wide " \
                              "reset would discard concurrent work in this shared checkout")
      end

      # Scoped, so the checkpoint being empty is not a reason to skip: it means
      # the path was unmodified then, and restoring it to HEAD is exactly right.
      # The old early return here is why a write that dirtied a clean tree and
      # then failed was never undone at all.
      restore_path(path, checkpoint[:patch])
      Observation.ok("rolled back #{path} #{checkpoint[:id]}")
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

      # Model-chosen env used to ride through (LD_PRELOAD, PATH, …). The
      # constitution only inspects argv. Inherit nothing from the effect.
      _ignored_env = env
      seconds = timeout.to_i
      seconds = EXEC_TIMEOUT if seconds <= 0 || seconds > EXEC_TIMEOUT

      # A name mapped to nil is UNSET in the child. Passing "ENV minus credentials"
      # would do nothing instead: spawn MERGES an env hash over the inherited
      # environment, so every dropped key would be inherited straight back.
      # Unsetting by name is also why the toolchain needs no enumerating —
      # everything not matched here arrives exactly as it did before.
      out, status = bounded_capture2e(
        *argv,
        env: ENV.keys.grep(CREDENTIAL_ENV_RX).to_h { |name| [name, nil] },
        chdir: @root,
        timeout: seconds,
      )
      status.success? ? Observation.ok(out.to_s.strip) : Observation.no(out.to_s.strip)
    end

    # Credentials do not go into the child, because the child's output comes back.
    #
    # `env: nil` inherited the whole process environment. That was written to mean
    # "nothing the MODEL supplied rides through", and it does mean that — but the
    # process running the fold holds OPENROUTER_API_KEY, ANTHROPIC_API_KEY,
    # REPLICATE_API_TOKEN and the rest, and exec output becomes an Observation,
    # which Memory records, which the next turn hands back to the model. So
    # `exec(["env"])` was a supported way to read every key into the transcript.
    #
    # no_secret_rule already forbids a secret reaching a file or a note. It watches
    # write and note only, so the exec path — the one that flows INTO the model
    # rather than out of it — was the direction nothing covered.
    #
    # Removed by name rather than allowlisted by name. An allowlist is the safer
    # shape in general, but here it would have to enumerate the toolchain the fold
    # proves its work with — PATH, HOME, GEM_*, BUNDLE_*, RBENV_*, RUBY* — and the
    # first variable it forgot would break `bundle exec rake test`, i.e. the fold's
    # ability to earn evidence at all. Credential names are the narrow, stable set;
    # the toolchain is the broad, moving one. This drops the narrow set.
    CREDENTIAL_ENV_RX = /KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|SESSION|COOKIE|SALT|CERT|PRIVATE|
                         \A(?:AWS|GOOGLE|GCP|AZURE|STRIPE|TWILIO|SENDGRID|VAPID|DATABASE_URL)/xi


    # commit is path-scoped, and refuses to run without paths.
    #
    # `git commit -m msg` commits THE INDEX, which in this repo is shared: the
    # checkout is one working tree that several sessions and a human use at
    # once, so whatever anyone else had staged went into the fold's commit under
    # the fold's message. That is the exact failure CLAUDE.md forbids agents from
    # causing ("commit path-scoped at minimum"), and the fold was the one agent
    # not doing it.
    #
    # `git commit -- <paths>` commits the working-tree state of those paths and
    # ignores the index entirely, which is what makes it safe here. The cost is
    # that this form cannot express a deletion; a fold that needs one has to say
    # so as its own effect rather than have it ride along invisibly.
    #
    # Empty paths is refused rather than defaulted. Defaulting to "everything I
    # touched" would be a guess about intent made by the layer with the least
    # information, and the failure it guesses wrong about is unrecoverable.
    def do_git(operation:, paths: [], message: nil, **)
      case operation.to_s.to_sym
      when :diff then Observation.ok(git_capture("diff"))
      when :stage then Observation.ok(git_capture("add", "--", *Array(paths)))
      when :commit then do_git_commit(Array(paths), message)
      else Observation.no("unknown git operation: #{operation}")
      end
    end

    def do_git_commit(paths, message)
      scoped = paths.map(&:to_s).reject(&:empty?)
      return Observation.no("git commit needs paths: an unscoped commit takes the shared index") if scoped.empty?

      Observation.ok(git_capture("commit", "-m", message.to_s, "--", *scoped))
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
      raise "path escapes workspace: #{path}" unless under_root?(abs, @root)

      # expand_path does not follow a symlink the agent just created with ln.
      # realpath of the existing ancestor must still sit under the real root.
      real_root = File.realpath(@root)
      existing = abs
      existing = File.dirname(existing) until File.exist?(existing)
      raise "path escapes workspace: #{path}" unless under_root?(File.realpath(existing), real_root)

      abs
    end

    def under_root?(abs, root)
      abs == root || abs.start_with?(root + File::SEPARATOR)
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

    # Bounded subprocess call with a hard timeout, which means killing the child
    # — not just abandoning it.
    #
    # This used to wrap Open3.capture3 in Timeout.timeout. Timeout only unwinds
    # the *block*; the process it spawned keeps running, and Ruby then blocks at
    # exit waiting for it. Measured: a 1s timeout around `sleep 30` took the full
    # 30 seconds to return, so the bound this method exists to provide did not
    # exist. popen3 gives us the pid, so the deadline can actually be enforced:
    # TERM, a short grace period, then KILL.
    def bounded_capture2e(*cmd, stdin_data: nil, env: nil, chdir: nil, timeout: nil)
      timeout_sec = Integer(timeout || ENV.fetch("MASTER_EXEC_TIMEOUT", EXEC_TIMEOUT))
      popen = env ? [env, *cmd] : cmd
      opts = {}
      opts[:chdir] = chdir if chdir

      Open3.popen3(*popen, pgroup: true, **opts) do |stdin, stdout, stderr, wait_thread|
        write_stdin(stdin, stdin_data)
        # Readers run off-thread: a child that fills its stdout pipe blocks on
        # write, so draining only after wait_thread returns would deadlock
        # exactly the wedged process this bound is for.
        out_reader = Thread.new { stdout.read }
        err_reader = Thread.new { stderr.read }

        unless wait_thread.join(timeout_sec)
          terminate(wait_thread.pid)
          [out_reader, err_reader].each(&:kill)
          next ["TIMEOUT after #{timeout_sec}s: #{cmd.first}", TIMED_OUT]
        end

        out = "#{out_reader.value}#{err_reader.value}"
        [out, wait_thread.value]
      end
    end

    def write_stdin(stdin, data)
      stdin.write(data) if data
      stdin.close
    rescue Errno::EPIPE
      # The child exited before reading its input; its status is the real signal.
      nil
    end

    # TERM first so the child can clean up, KILL if it ignores that. ESRCH means
    # it exited between the join timing out and this call — already gone.
    def terminate(pid)
      target = -Process.getpgid(pid)
      Process.kill("TERM", target)
      return if wait_for_exit(pid, TERM_GRACE)

      Process.kill("KILL", target)
      wait_for_exit(pid, TERM_GRACE)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def wait_for_exit(pid, seconds)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      until Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        return true if Process.waitpid(pid, Process::WNOHANG)

        sleep 0.02
      end
      false
    rescue Errno::ECHILD
      true
    end

    # Bounded like every other git call here. This is rollback's no-HEAD path;
    # leaving it on raw Open3 meant a wedged git could hang rollback forever,
    # which is exactly the failure the bound exists to prevent.
    def apply_patch_reverse(patch)
      out, status = bounded_capture2e("git", "-C", @root, "apply", "--reverse", "--binary", "-", stdin_data: patch)
      raise out.strip unless status.success?
    end

    # Only a write names its target up front. exec can touch anything, and git
    # operations are undone by git rather than by a patch.
    def rollback_path(effect)
      effect.args[:path].to_s.then { |p| p unless p.empty? } if effect.respond_to?(:verb) && effect.verb == :write
    end

    # Restore one path to the state the checkpoint captured.
    #
    # Two steps because the patch is a diff against HEAD: put the file back to
    # HEAD, then re-apply only this path's hunks from the checkpoint. --include
    # is what keeps the rest of the patch — other files, other sessions' work —
    # out of it.
    #
    # A path git does not know at HEAD is left exactly as it is. It could be a
    # file the effect created, but it could equally be an untracked file that was
    # already there, and nothing captured at checkpoint time tells the two apart.
    # Deleting on that guess is the one outcome that cannot be undone, and
    # test_world_rollback already pins that a pre-existing untracked file survives.
    def restore_path(path, patch)
      raise "#{path} is untracked at HEAD; left alone rather than guessed to be new" unless tracked_at_head?(path)

      git_capture("checkout", "HEAD", "--", path)
      apply_patch_for(path, patch)
    end

    def tracked_at_head?(path)
      return false unless git_has_head?

      out, status = bounded_capture2e("git", "-C", @root, "ls-tree", "--name-only", "HEAD", "--", path)
      status.success? && !out.strip.empty?
    end

    # An empty selection is not a failure: the path had no uncommitted change at
    # checkpoint time, so HEAD is already the state being restored to.
    def apply_patch_for(path, patch)
      out, status = bounded_capture2e("git", "-C", @root, "apply", "--binary", "--include=#{path}", "-",
                                      stdin_data: patch)
      raise out.strip unless status.success? || out.include?("No valid patches")
    end
  end
end
