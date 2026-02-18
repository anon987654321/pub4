# frozen_string_literal: true

module MASTER
  module Commands
    # System commands: schedule, heartbeat, policy
    module SystemCommands
      def manage_schedule(args)
        parts = args.to_s.strip.split(/\s+/)
        subcmd = parts.shift
        Scheduler.load

        case subcmd
        when "list"
          list_scheduled_jobs
        when "add"
          add_scheduled_job(parts)
        when "remove", "enable", "disable"
          toggle_scheduled_job(subcmd, parts[0])
        else
          show_schedule_usage
        end

        HANDLED
      end

      def manage_heartbeat(args)
        parts = args.to_s.strip.split(/\s+/)
        subcmd = parts.shift

        case subcmd
        when "start"
          start_heartbeat(parts)
        when "stop"
          Heartbeat.stop
          puts "Heartbeat stopped"
        when "status"
          show_heartbeat_status
        else
          puts "Usage: heartbeat start [interval_sec]|stop|status"
        end

        HANDLED
      end

      def manage_policy(args)
        parts = args.to_s.strip.split(/\s+/)
        subcmd = parts.shift

        case subcmd
        when "set"
          result = AgentFirewall::Policy.set(parts[0]&.to_sym)
          puts result.ok? ? "Policy: #{result.value[:profile]}" : result.error
        else
          puts "Current policy: #{AgentFirewall::Policy.current}"
          puts "Available: #{AgentFirewall::Policy::PROFILES.keys.join(', ')}"
        end

        HANDLED
      end

      private

      def list_scheduled_jobs
        jobs = Scheduler.list
        if jobs.empty?
          puts "No scheduled jobs"
        else
          jobs.each { |j| puts "#{j[:id]}  #{j[:enabled] ? '✓' : '✗'}  every #{j[:interval]}s  #{j[:command]}" }
        end
      end

      def add_scheduled_job(parts)
        cmd = parts[0]
        interval = (parts[1] || "3600").to_i
        result = Scheduler.add(cmd, interval: interval)
        puts result.ok? ? "Scheduled: #{result.value[:job_id]}" : result.error
      end

      def toggle_scheduled_job(action, job_id)
        result = case action
        when "remove" then Scheduler.remove(job_id)
        when "enable" then Scheduler.enable(job_id)
        when "disable" then Scheduler.disable(job_id)
        end
        puts result.ok? ? action.capitalize : result.error
      end

      def show_schedule_usage
        puts "Usage: schedule list|add <cmd> [interval_sec]|remove <id>|enable <id>|disable <id>"
      end

      def start_heartbeat(parts)
        interval = (parts[0] || "60").to_i
        Triggers.install_defaults
        Scheduler.load
        Heartbeat.register("scheduler") { Scheduler.tick }
        Heartbeat.start(interval: interval)
        puts "Heartbeat started (#{interval}s interval). Press Ctrl+C to stop."
        sleep
      end

      def show_heartbeat_status
        s = Heartbeat.status
        puts "running=#{s[:running]} interval=#{s[:interval]}s checks=#{s[:checks].size}"
        s[:checks].each { |c| puts "  #{c[:name]} last=#{c[:last_run]} failures=#{c[:failures]}" }
      end
    end
  end
end
