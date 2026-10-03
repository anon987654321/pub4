# frozen_string_literal: true

require_relative "../../trace/self_evolution_trigger"

module Master
  module CLI
    module CommandRegistry
      module_function

      # Directories the boot tree never descends into: dependencies, build output
      # and runtime state.
      SKIP_SEGS = %w[
        .git .master vendor tmp var node_modules .bundle coverage log dist knowledge
        runtime .venv renders storage quarantine .cache
      ].freeze

      COMMIT_USAGE = "usage: /commit <path>... --confirm — name what goes in. Other sessions " \
                     "edit this checkout, so a commit that sweeps up every change is refused."

      # /commit — stage and commit the named paths, and only those, with a
      # model-written message. The checkout is shared by several sessions, so
      # `git add -u` would publish another session's half-finished work under
      # this one's message; the path list is the scope, and git enforces it
      # with `commit -- <paths>`. Paths are relative to the runtime root.
      def dispatch_commit(agent, root, ctx: nil)
        paths = arg_for(ctx).split(/\s+/).reject(&:empty?)
        return COMMIT_USAGE if paths.empty?

        evolution = Master::Trace::SelfEvolutionTrigger.new(root:).call
        changed, = Master::Io::Exec.capture2e("git", "-C", root, "status", "--porcelain", "--", *paths)
        return "commit: nothing to commit in #{paths.join(' ')}" if changed.strip.empty?

        diff, = Master::Io::Exec.capture2e("git", "-C", root, "diff", "HEAD", "--stat", "--", *paths)
        prompt = "Write a concise git commit message (1 line, imperative mood) for:\n#{diff}\n#{changed}"
        message = agent.ask_once(prompt).to_s.strip.lines.first.to_s.strip
        return "commit: no message came back, so nothing was committed" if message.empty?

        Master::Io::Exec.capture2e("git", "-C", root, "add", "--", *paths)
        out, = Master::Io::Exec.capture2e("git", "-C", root, "commit", "-m", message,
                                          "-m", Master::Core::World::COMMIT_TRAILER, "--", *paths)
        [evolution, out.strip].reject(&:empty?).join("\n")
      end

      # The tree the session prints on first boot.
      def dispatch_tree(root, ctx: nil)
        arg = arg_for(ctx)
        cfg = (Master.load_rules(root:) || {}).dig("paths", "tree") || {}
        depth = arg.to_i.positive? ? arg.to_i : (cfg["max_depth"] || 2)
        cap = cfg["max_lines"] || 200
        tree_lines = []
        walk_tree(root, 1, depth:, cap:, tree_lines:)
        tree_lines.join("\n")
      end

      def walk_tree(dir, level, depth:, cap:, tree_lines:)
        return if level > depth || tree_lines.size >= cap

        Dir.children(dir).sort.each do |name|
          break if tree_lines.size >= cap
          next if name.start_with?(".") || SKIP_SEGS.include?(name)

          path = File.join(dir, name)
          tree_lines << "#{" " * (level - 1)}#{name}#{File.directory?(path) ? "/" : ""}"
          walk_tree(path, level + 1, depth:, cap:, tree_lines:) if File.directory?(path)
        end
      rescue Errno::EACCES, Errno::ENOENT => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.walk_tree")
        nil
      end
    end
  end
end
