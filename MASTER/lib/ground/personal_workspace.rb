# frozen_string_literal: true

require "fileutils"
require_relative "personal_permissions"

module Master
  module Ground
    # Per-paired-subject USER.md + MEMORY.md. Injected each turn. Lives under
    # .master/workspace/ — gitignored, never the shared project_context.yml.
    module PersonalWorkspace
      MAX_BYTES = 4_096
      MAX_EXPORT_BYTES = 16_384
      REL = ".master/workspace"
      MEMORY_PERMISSION_PURPOSE = "read and write personal profile and memory".freeze

      class PermissionDenied < StandardError; end
      class ExportTooLarge < StandardError; end
      USER_STUB = <<~MD
        # USER

        Name and preferences for this paired session. This is not the operator.
      MD
      MEMORY_STUB = <<~MD
        # MEMORY

        Durable notes for this paired subject. The heartbeat returns HEARTBEAT_OK when nothing here needs a nudge.
      MD

      module_function

      def dir_for(subject, root: Master::ROOT)
        File.join(root, REL, sanitize(subject))
      end

      def ensure!(root: Master::ROOT, subject:)
        state_dir = File.join(root, ".master")
        workspace = File.join(root, REL)
        dir = dir_for(subject, root:)
        if [state_dir, workspace, dir].any? { |path| File.symlink?(path) }
          raise PermissionDenied, "personal workspace paths must not be symlinks"
        end

        FileUtils.mkdir_p(dir, mode: 0o700)
        File.chmod(0o700, workspace)
        File.chmod(0o700, dir)
        ensure_private_file(File.join(dir, "USER.md"), USER_STUB)
        ensure_private_file(File.join(dir, "MEMORY.md"), MEMORY_STUB)
        dir
      end

      # An owner-requested, bounded view/export. This never enters model context
      # and refuses oversize data rather than quietly returning a partial export.
      def snapshot(root:, subject:)
        unless permission_granted?(root:, subject:)
          raise PermissionDenied, "personal profile and memory are disabled"
        end

        dir = ensure!(root:, subject:)
        paths = %w[USER.md MEMORY.md].to_h { |name| [name, File.join(dir, name)] }
        total = paths.values.sum do |path|
          raise PermissionDenied, "personal workspace files must not be symlinks" if File.symlink?(path)
          raise PermissionDenied, "personal workspace file is not a regular file" unless File.file?(path)

          File.size(path)
        end
        if total > MAX_EXPORT_BYTES
          raise ExportTooLarge, "personal export exceeds #{MAX_EXPORT_BYTES} bytes; inspect the workspace files locally"
        end

        paths.transform_values do |path|
          value = File.read(path, encoding: "UTF-8")
          raise PermissionDenied, "personal workspace contains invalid UTF-8" unless value.valid_encoding?

          value
        end
      end

      # Clears durable memory only. The profile survives. The command layer must
      # require explicit confirmation before invoking this method.
      def forget_memory!(root:, subject:)
        unless permission_granted?(root:, subject:)
          raise PermissionDenied, "personal profile and memory are disabled"
        end

        dir = ensure!(root:, subject:)
        path = File.join(dir, "MEMORY.md")
        raise PermissionDenied, "personal workspace files must not be symlinks" if File.symlink?(path)

        File.open(path, "w", 0o600) do |io|
          io.write(MEMORY_STUB)
          io.flush
          io.fsync
        end
        File.chmod(0o600, path)
        true
      end

      def prompt_section(root = Master::ROOT, subject = Fiber[:master_pair_subject])
        if subject.to_s.strip.empty? && Fiber[:master_visitor] != true && defined?(Master::Device::Agent) &&
            Master::Device.android? && Master::Device::Agent.paired?(root:)
          subject = Master::Device::Agent.owner_subject(root:)
        end
        return unless permission_granted?(root:, subject:)

        dir = dir_for(subject, root:)
        user = read_capped(File.join(dir, "USER.md"))
        memory = read_capped(File.join(dir, "MEMORY.md"))
        return if user.nil? && memory.nil?

        parts = ["## Personal workspace (paired)"]
        parts << "### USER.md\n#{user}" if user
        parts << "### MEMORY.md\n#{memory}" if memory
        parts.join("\n\n")
      end

      def append_memory(root:, subject:, key:, body:, type: "general")
        unless permission_granted?(root:, subject:)
          raise PermissionDenied, "personal profile and memory are disabled; use /privacy grant personal_memory in the local paired session"
        end

        ensure!(root:, subject:)
        path = File.join(dir_for(subject, root:), "MEMORY.md")
        stamp = Time.now.utc.strftime("%Y-%m-%d")
        File.open(path, "a") { |io| io.write("\n\n## #{stamp} #{type} #{key}\n\n#{body.to_s.strip}\n") }
        path
      end

      def pulse(root: Master::ROOT)
        Dir.glob(File.join(root, REL, "*", "MEMORY.md")).each do |path|
          body = File.read(path, encoding: "UTF-8")
          hits = body.each_line.grep(/\A\s*(?:TODO|NUDGE):/i).map(&:strip)
          next if hits.empty?

          subject = File.basename(File.dirname(path))
          return "pulse: #{subject} #{hits.first}"
        end
        "HEARTBEAT_OK"
      rescue StandardError
        "HEARTBEAT_OK"
      end

      def permission_granted?(root:, subject:)
        id = subject.to_s.strip
        return false if id.empty?

        PersonalPermissions.new(root:).allowed?(
          scope: "personal_memory", subject: id, purpose: MEMORY_PERMISSION_PURPOSE,
        )
      end

      def sanitize(subject)
        subject.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")[0, 32]
      end

      def read_capped(path)
        return if File.symlink?(path) || !File.file?(path)

        body = File.read(path, encoding: "UTF-8").strip
        return if body.empty?

        body.byteslice(0, MAX_BYTES)
      end

      def ensure_private_file(path, stub)
        raise PermissionDenied, "personal workspace files must not be symlinks" if File.symlink?(path)

        unless File.exist?(path)
          File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |io| io.write(stub) }
        end
        raise PermissionDenied, "personal workspace file is not a regular file" unless File.file?(path)

        File.chmod(0o600, path)
      end
    end
  end
end
