# frozen_string_literal: true

require_relative "../io/exec"

module Operator
  # Publishes this checkout's unpublished main commits when origin/main has moved
  # and the shared tree is too dirty to rebase. `land` rebases, and a rebase
  # refuses a working tree holding other sessions' files; stashing them to make
  # room is how another session's edits went missing mid-pass.

  # So nothing here touches the working tree until the push is confirmed. Each
  # commit in origin/main..HEAD is replayed in order with
  # `git merge-tree --write-tree --merge-base=<parent> <tip> <commit>` and
  # `git commit-tree`, keeping its author and message, onto origin/main. Any
  # conflict refuses the whole run before anything is pushed. The new tip is
  # pushed without force, read back from the remote, and only then does
  # `git reset --keep` move this checkout onto it. reset --keep refuses rather
  # than overwrite a file someone has changed locally.
  class ReplayPush

    Refused = Class.new(StandardError)
    REMOTE = "origin"
    BRANCH = "main"
    UPSTREAM = "refs/remotes/#{REMOTE}/#{BRANCH}".freeze
    REMOTE_REF = "refs/heads/#{BRANCH}".freeze

    # The git calls, each returning its output and whether it succeeded, so the
    # replay reads as the steps it takes.
    class Git
      Result = Data.define(:out, :ok)
      # A push runs pre-push, whose snapshot and boot smoke take most of a minute.
      TIMEOUT_S = 600

      def initialize(root) = @root = root

      def run(*args, env: {}, stdin: nil)
        out, err, status = Master::Io::Exec.capture3(env, "git", *args, chdir: @root, timeout: TIMEOUT_S,
                                                     stdin_data: stdin)
        Result.new(out: out + err, ok: status.success?)
      end

      def run!(*args, **)
        result = run(*args, **)
        raise Refused, "git #{args.first} failed: #{result.out.strip}" unless result.ok

        result.out
      end

      def rev(name) = run!("rev-parse", "--verify", "-q", name).strip

      def subject(sha) = run!("log", "-1", "--format=%s", sha).strip

      def ancestor?(older, newer) = run("merge-base", "--is-ancestor", older, newer).ok

      # A new commit of +tree+ on +parent+ with +sha+'s author and message.
      def commit_as(sha, tree:, parent:)
        name, email, date = run!("log", "-1", "--format=%an%x00%ae%x00%ad", "--date=raw", sha).chomp.split("\0", 3)
        message = run!("cat-file", "commit", sha).split("\n\n", 2).last.to_s
        env = { "GIT_AUTHOR_NAME" => name, "GIT_AUTHOR_EMAIL" => email, "GIT_AUTHOR_DATE" => date }

        run!("commit-tree", tree, "-p", parent, env:, stdin: message).strip
      end

      def remote_head = run!("ls-remote", REMOTE, REMOTE_REF).split.first.to_s
    end

    def initialize(root:, out: $stdout)
      @git = Git.new(root)
      @out = out
    end

    # true when there was nothing to push or the push and the reset both landed.
    def run
      @git.run!("fetch", "-q", REMOTE)
      on_branch!
      local = @git.rev("HEAD")
      commits = unpublished
      return say("push0: nothing on #{BRANCH} that #{REMOTE} lacks") if commits.empty?

      tip = publish!(rebuild(local, commits))
      settle(tip, local)
    rescue Refused => e
      say("push0: refused, #{e.message}")
      false
    end

    private

    def on_branch!
      head = @git.run("symbolic-ref", "-q", "HEAD").out.strip
      return if head == "refs/heads/#{BRANCH}"

      raise Refused, "HEAD is #{head.empty? ? "detached" : head}, not refs/heads/#{BRANCH}"
    end

    # Oldest first. A merge commit has no single parent to replay against, so
    # the run refuses rather than flatten it.
    def unpublished
      shas = @git.run!("rev-list", "--reverse", "--topo-order", "#{UPSTREAM}..HEAD").split
      merges = shas.select { |sha| @git.run!("rev-list", "--parents", "-n1", sha).split.size > 2 }
      return shas if merges.empty?

      raise Refused, "#{merges.map { |sha| sha[0, 9] }.join(", ")} is a merge commit; replay pushes linear history only"
    end

    # When origin/main is already beneath HEAD there is nothing to replay: the
    # commits go as they are and keep their hashes.
    def rebuild(local, commits)
      if @git.ancestor?(UPSTREAM, local)
        return commits.map { |sha| Replayed.new(old: sha, new: sha, subject: @git.subject(sha)) }
      end

      tip = @git.rev(UPSTREAM)
      commits.filter_map do |sha|
        replayed = replay(sha, tip)
        unless replayed
          say("push0: #{sha[0, 9]} already on #{REMOTE}, dropped: #{@git.subject(sha)}")
          next
        end

        tip = replayed.new
        replayed
      end
    end

    def replay(sha, tip)
      merged = @git.run("merge-tree", "--write-tree", "--merge-base=#{sha}^", tip, sha)
      conflict!(sha, merged.out) unless merged.ok
      tree = merged.out.lines.first.strip
      return if tree == @git.rev("#{tip}^{tree}")

      Replayed.new(old: sha, new: @git.commit_as(sha, tree:, parent: tip), subject: @git.subject(sha))
    end

    def conflict!(sha, report)
      files = report.lines.drop(1).map(&:strip).reject(&:empty?).first(8)
      raise Refused, "#{sha[0, 9]} #{@git.subject(sha)} conflicts with #{REMOTE}/#{BRANCH}: #{files.join("; ")}"
    end

    # Without force: if origin moved again since the fetch, git refuses and the
    # checkout is left exactly as it was.
    def publish!(replayed)
      tip = replayed.last&.new || @git.rev(UPSTREAM)
      replayed.each { |r| say(r.line) }
      pushed = @git.run("push", REMOTE, "#{tip}:#{REMOTE_REF}")
      raise Refused, "git push failed, nothing reset:\n#{pushed.out.strip}" unless pushed.ok

      remote_tip = @git.remote_head
      return tip if remote_tip == tip

      raise Refused, "#{REMOTE}/#{BRANCH} reads #{remote_tip[0, 9]} after the push, not #{tip[0, 9]}; nothing reset"
    end

    def settle(tip, local)
      return say("push0: #{REMOTE}/#{BRANCH} at #{tip[0, 9]}") if tip == local

      reset = @git.run("reset", "--keep", tip)
      return say("push0: #{REMOTE}/#{BRANCH} and #{BRANCH} at #{tip[0, 9]}") if reset.ok

      say("push0: pushed #{tip[0, 9]}, but reset --keep refused; #{BRANCH} is still #{local[0, 9]}:")
      say(reset.out.strip)
      false
    end

    def say(line)
      @out.puts(line)
      true
    end
  end

  # One commit's hash before and after the replay, as the push prints it.
  ReplayPush::Replayed = Data.define(:old, :new, :subject) do
    def line = "push0: #{old[0, 9]} -> #{new[0, 9]} #{subject}"
  end
end
