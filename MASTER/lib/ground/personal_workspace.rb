# frozen_string_literal: true

require "fileutils"

module Master
  module Ground
    # Per-paired-subject USER.md + MEMORY.md. Injected each turn. Lives under
    # .master/workspace/ — gitignored, never the shared project_context.yml.
    module PersonalWorkspace
      MAX_BYTES = 4_096
      REL = ".master/workspace"
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
        dir = dir_for(subject, root:)
        FileUtils.mkdir_p(dir)
        user = File.join(dir, "USER.md")
        memory = File.join(dir, "MEMORY.md")
        File.write(user, USER_STUB) unless File.file?(user)
        File.write(memory, MEMORY_STUB) unless File.file?(memory)
        dir
      end

      def prompt_section(root = Master::ROOT, subject = Fiber[:master_pair_subject])
        return unless subject.to_s.strip != ""

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

      def sanitize(subject)
        subject.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")[0, 32]
      end

      def read_capped(path)
        return unless File.file?(path)

        body = File.read(path, encoding: "UTF-8").strip
        return if body.empty?

        body.byteslice(0, MAX_BYTES)
      end
    end
  end
end
