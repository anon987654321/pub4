# frozen_string_literal: true

require_relative "../io/exec"

module Master
  module CLI
    # CouncilCrit — run the persona council on a git diff artifact (in-process).
    module CouncilCrit
      MAX_DIFF_BYTES = 32_000

      module_function

      def run(root:, deliberation:, scope: "diff", bus: nil)
        artifact = diff_artifact(root, scope:)
        return Master::Result.ok("critique: no changes to review") if artifact.strip.empty?
        return Master::Result.err("critique: deliberation unavailable", category: :infrastructure) unless deliberation

        bus&.publish("council:start", scope:, bytes: artifact.bytesize)
        result = deliberation.review(artifact, context: "pre-ship council check (#{scope})")
        if result.err?
          bus&.publish("council:veto", message: result.message.to_s[0, 500])
          return result
        end

        feedback = result.value!
        summary = tribunal_summary(feedback)
        bus&.publish("council:pass", jurors: feedback.size)
        Master::Result.ok(summary)
      # Programming defects must escape this boundary. Converting a missing
      # method or malformed type into an ordinary Result would let the pipeline
      # report a failed council as if it were a normal critique reading.
      rescue NameError, TypeError
        raise
      rescue StandardError => e
        Master::Result.err("critique: #{e.message}", category: :infrastructure)
      end

      def runner_for(container)
        lambda do |root:, scope: "diff"|
          run(
            root:,
            deliberation: container[:deliberation],
            scope:,
            bus: container[:bus],
          )
        end
      end

      # root may name a file: the repository is its directory and the diff is limited to it.
      def diff_artifact(root, scope:)
        repo = File.directory?(root) ? root : File.dirname(root)
        only = File.directory?(root) ? [] : %w[--].push(root)

        case scope.to_s
        when "diff", "" then git_capture(repo, "diff", "HEAD", *only)
        when "staged" then git_capture(repo, "diff", "--cached", *only)
        else git_capture(repo, "diff", "HEAD", "--", scope)
        end
      end

      def git_capture(root, *args)
        out, status = Master::Io::Exec.capture2e("git", "-C", root, *args)
        # A pipe read comes back tagged binary, and the personas' prompts join this to UTF-8 text.
        text = out.to_s.dup.force_encoding(Encoding::UTF_8).scrub
        unless status.success?
          detail = text.lines.last(8).join.strip
          raise "git #{args.join(" ")} failed#{detail.empty? ? "" : ": #{detail}"}"
        end

        return text if text.bytesize <= MAX_DIFF_BYTES

        "#{text.byteslice(0, MAX_DIFF_BYTES).scrub}\n… [truncated]"
      end

      def tribunal_summary(feedback)
        lines = feedback.reject { |e| e[:role] == "Synthesis" }.first(6).map do |entry|
          "#{entry[:persona]}: #{entry[:feedback].to_s.strip.lines.first.to_s[0, 120]}"
        end
        judge = feedback.find { |e| e[:role] == "Synthesis" }
        lines << "synthesis: #{judge[:feedback].to_s.strip[0, 200]}" if judge
        ["critique: council pass", *lines].join("\n")
      end
    end
  end
end
