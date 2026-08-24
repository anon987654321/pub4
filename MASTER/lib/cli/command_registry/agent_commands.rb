# frozen_string_literal: true

require "fileutils"

module Master
  module CLI
    module CommandRegistry
      module_function

      def agent_commands(agent:, agent_pool:, shell:, root:, bus:, session: nil)
        {
          "btw" => command(:dispatch_btw, agent_pool, agent, bus),
          "rtk" => command(:dispatch_rtk, root),
          "shell" => command(:dispatch_shell, shell),
          "plan" => command(:dispatch_plan, root, bus),
          "rebuild" => command(:dispatch_rebuild, session, root),
        }
      end

      def dispatch_btw(agent_pool, agent, bus, ctx: nil)
        return "btw: agent pool not configured" unless agent_pool

        arg = arg_for(ctx)
        return "usage: /btw <explore|plan|code|research|verify> <task>" if arg.strip.empty?

        type, task = arg.split(/\s+/, 2)
        return "usage: /btw <type> <task>" if task.to_s.strip.empty?

        parsed = Ground::Policy::Subagent.parse(type)
        spawn = agent_pool.spawn(type: parsed, tag: "btw") do
          prompt = "#{Ground::Policy::Subagent.prompt_for(parsed)}\n\nTask:\n#{task}"
          summary = agent.ask_once(prompt).to_s.strip
          bus&.publish("btw:done", type: parsed, summary: summary[0, 4_000])
          bus&.publish("agent:plan_done", summary:) if parsed == :plan
        end
        return spawn.message if spawn.err?

        "btw: #{parsed} agent started (#{agent_pool.active_count} active) — watch for btw:done"
      end

      def dispatch_rtk(root, ctx: nil)
        stats = Io::OutputFilter.stats(root)
        saved = stats.fetch("bytes_in", 0) - stats.fetch("bytes_out", 0)
        pct = stats.fetch("saved_pct", 0.0)
        last = stats["last_command"]
        lines = [
          "RTK output filter stats",
          "commands: #{stats.fetch('commands', 0)}",
          "bytes in: #{stats.fetch('bytes_in', 0)}",
          "bytes out: #{stats.fetch('bytes_out', 0)}",
          "saved: #{saved}B (#{pct}%)",
        ]
        lines << "last: #{last}" if last
        lines.join("\n")
      end

      def dispatch_shell(shell, ctx: nil)
        cmd = arg_for(ctx)
        return "usage: /shell <command>  (or !cmd in web)" if cmd.empty?
        return "shell: not configured" unless shell

        result = shell.call(command: cmd)
        result.ok? ? result.value!.to_s : result.message
      end

      def dispatch_rebuild(session, root, ctx: nil)
        session&.save! if session.respond_to?(:save!)
        web_restart = File.join(root, "web", "tmp", "restart.txt")
        if File.directory?(File.dirname(web_restart))
          FileUtils.mkdir_p(File.dirname(web_restart))
          FileUtils.touch(web_restart)
          return "rebuild: web face restart triggered (tmp/restart.txt)"
        end

        lib_dir = File.join(root, "lib")
        errors = Dir.glob(File.join(lib_dir, "**", "*.rb")).select do |path|
          !system(RbConfig.ruby, "-c", path, out: File::NULL, err: File::NULL)
        end
        return "rebuild: aborted — syntax errors in #{errors.size} file(s)" if errors.any?

        session&.save! if session.respond_to?(:save!)
        ::Kernel.exec(RbConfig.ruby, $PROGRAM_NAME, *ARGV)
      rescue StandardError => e
        "rebuild: #{e.message}"
      end

      def dispatch_plan(root, bus, ctx: nil)
        arg = arg_for(ctx)
        if arg.empty?
          body = Ground::ActivePlan.read(root)
          return body || "(no active plan — set with /plan <markdown tasks>)"
        end

        if arg == "clear"
          Ground::ActivePlan.clear(root, bus:)
          return "plan cleared"
        end

        Ground::ActivePlan.pin(root, arg, bus:)
        "plan pinned (#{arg.lines.count} lines)"
      end
    end
  end
end
