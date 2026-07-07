# frozen_string_literal: true

require "open3"

module Master
  module Now
    class ResyncService
      def initialize(root:, fix_loop: nil, git: nil, bus: nil)
        @root = root
        @repo = File.expand_path("..", root)
        @fix_loop = fix_loop
        @git = git || Reach::GitOperations.new(@repo)
        @bus = bus
      end

      def call(dry_run: false)
        lines = [start_line]
        lines << "  tagged #{tag_name}" unless dry_run
        return dry_run_lines(lines) if dry_run

        execute_resync(lines)
      rescue StandardError => e
        "resync: #{e.message}"
      end

      private

      attr_reader :root, :repo, :fix_loop, :git, :bus

      def start_line
        stop_msg = fix_loop&.background_alive? ? (fix_loop.stop_background!; "stopped fix_loop bg; ") : ""
        "#{stop_msg}resync starting — tag=#{tag_name} was=#{old_head}"
      end

      def execute_resync(lines)
        git.tag(tag_name)
        git.fetch
        lines << "  fetched origin"
        git.reset_hard("origin/main")
        lines << "  reset --hard origin/main → #{git.head}"
        bus&.publish("resync:reset", tag: tag_name, head: git.head, was: old_head)
        lines << bundle_install_line(File.join(repo, "MASTER"), "MASTER")
        lines << bundle_install_line(File.join(repo, "MASTER/web"), "MASTER/web")
        Master::Reach::Exec.capture2e("doas", "rcctl", "restart", "master")
        sleep 2
        lines << "  rcctl restart master — #{CommandRegistry.service_status[:state]}"
        bus&.publish("deploy:restart", service: "master", state: CommandRegistry.service_status[:state])
        lines.join("\n")
      end

      def dry_run_lines(lines)
        git.fetch
        ahead, behind = git.ahead_behind
        (lines + ["  fetched origin", "  dry-run: would reset --hard origin/main (ahead=#{ahead} behind=#{behind})"]).join("\n")
      end

      def bundle_install_line(dir, label)
        out, status = Master::Reach::Exec.capture2e(Master::BUNDLE_BIN, "install", chdir: dir)
        ok = status.success? && out.include?("Bundle complete")
        "  bundle install #{label} — #{ok ? "ok" : "FAILED"}"
      rescue StandardError => e
        "  bundle install #{label} — error: #{e.message}"
      end

      def tag_name
        @tag_name ||= "backup/#{Time.now.strftime("%Y%m%d-%H%M")}-resync"
      end

      def old_head
        @old_head ||= git.head
      end
    end
  end
end
