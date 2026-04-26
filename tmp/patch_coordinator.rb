# Phase 5: Add shared deadline + dispatch_parallel to swarm coordinator
path = "/home/dev/pub4/MASTER/lib/master/swarm/coordinator.rb"
src = File.read(path)

# Add dispatch_parallel method after fan_out
old_fan_out_end = "      def worker_roles = WORKER_CLASSES.keys"

new_fan_out_end = <<~'RUBY'.chomp
      # Convenience: parallel dispatch with a shared wall-clock deadline.
      # role_tasks: [{role:, task:, context_slice: {}}]
      # deadline: total seconds for all workers (not per-worker).
      def dispatch_parallel(role_tasks, deadline: WORKER_TIMEOUT * 2)
        finish_by = Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline

        threads = role_tasks.map do |t|
          Thread.new do
            remaining = [finish_by - Process.clock_gettime(Process::CLOCK_MONOTONIC), 1].max
            Timeout.timeout(remaining) do
              [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
            end
          rescue Timeout::Error
            [t[:role], Result.err("worker exceeded shared deadline", category: :unknown)]
          end
        end

        results = threads.map { |th| th.join(deadline)&.value || [nil, Result.err("join timeout")] }.to_h
        synthesis = synthesize(results)
        @bus&.publish(:swarm_dispatch_parallel_done, roles: results.keys)
        Result.ok({ results: results, synthesis: synthesis })
      end

      def worker_roles = WORKER_CLASSES.keys
RUBY

src.sub!(old_fan_out_end, new_fan_out_end)

# Add require "timeout" at top
src.sub!('# frozen_string_literal: true', "# frozen_string_literal: true\n\nrequire \"timeout\"")

File.write(path, src)
puts "Coordinator patched"
puts `ruby -c #{path} 2>&1`
