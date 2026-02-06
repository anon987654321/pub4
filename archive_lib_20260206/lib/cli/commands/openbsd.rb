# frozen_string_literal: true

module MASTER
  class CLI
    module Commands
      module OpenBSD
        # OpenBSD native commands: rcctl, pfctl, doas, pkg_add, zap

        def cmd_services(args = nil)
          return "Not on OpenBSD" unless openbsd?

          if args.nil? || args.empty?
            # List all enabled services with status
            output = `rcctl ls on 2>/dev/null`.lines.map(&:strip)
            output.map do |svc|
              status = `rcctl check #{svc} 2>/dev/null`.strip
              running = status.include?('ok') ? '✓' : '✗'
              "  #{running} #{svc}"
            end.join("\n")
          else
            action, service = args.split(' ', 2)
            case action
            when 'start', 'stop', 'restart', 'reload'
              `doas rcctl #{action} #{service} 2>&1`
            when 'enable', 'disable'
              `doas rcctl #{action} #{service} 2>&1`
            when 'status'
              `rcctl check #{service} 2>&1`
            else
              "Usage: services [start|stop|restart|enable|disable|status] <service>"
            end
          end
        end

        def cmd_firewall(args = nil)
          return "Not on OpenBSD" unless openbsd?

          if args.nil? || args.empty?
            # Show current rules
            `doas pfctl -sr 2>/dev/null`
          else
            case args
            when 'reload'
              `doas pfctl -f /etc/pf.conf 2>&1`
            when 'disable'
              `doas pfctl -d 2>&1`
            when 'enable'
              `doas pfctl -e 2>&1`
            when 'stats'
              `doas pfctl -si 2>/dev/null`
            when 'tables'
              `doas pfctl -sT 2>/dev/null`
            else
              "Usage: firewall [reload|enable|disable|stats|tables]"
            end
          end
        end

        def cmd_pkg(args = nil)
          return "Not on OpenBSD" unless openbsd?

          if args.nil? || args.empty?
            # List installed packages
            `pkg_info -q 2>/dev/null`
          else
            action, pkg = args.split(' ', 2)
            case action
            when 'add', 'install'
              `doas pkg_add #{pkg} 2>&1`
            when 'delete', 'remove'
              `doas pkg_delete #{pkg} 2>&1`
            when 'search'
              `pkg_info -Q #{pkg} 2>/dev/null`
            when 'info'
              `pkg_info #{pkg} 2>/dev/null`
            when 'update'
              `doas pkg_add -u 2>&1`
            else
              "Usage: pkg [add|delete|search|info|update] <package>"
            end
          end
        end

        def cmd_zap(args = nil)
          return "Not on OpenBSD" unless openbsd?

          if args.nil? || args.empty?
            "Usage: zap <package> - Remove package and unused dependencies"
          else
            # zap removes package and cleans up
            `doas pkg_delete -a #{args} 2>&1`
          end
        end

        def cmd_sysinfo(_args = nil)
          return "Not on OpenBSD" unless openbsd?

          info = []
          info << "Hostname: #{`hostname`.strip}"
          info << "Uptime: #{`uptime`.strip}"
          info << "Kernel: #{`uname -a`.strip}"
          info << "Memory: #{`vmstat | tail -1`.strip}"
          info << "Disk: #{`df -h / | tail -1`.strip}"
          info << "Load: #{File.read('/proc/loadavg').strip rescue 'N/A'}"
          info.join("\n")
        end

        def cmd_ports(args = nil)
          return "Not on OpenBSD" unless openbsd?

          if args.nil? || args.empty?
            # Show listening ports
            `netstat -an -f inet | grep LISTEN`
          else
            `netstat -an -f inet | grep #{args}`
          end
        end

        private

        def openbsd?
          RUBY_PLATFORM.include?('openbsd')
        end
      end
    end
  end
end
