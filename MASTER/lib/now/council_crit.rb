# frozen_string_literal: true

require "open3"

module Master
  module Now
    # CouncilCrit — run the persona council on a git diff artifact (in-process).
    module CouncilCrit
      MAX_DIFF_BYTES = 32_000

      module_function

      def run(root:, deliberation:, scope: "diff", bus: nil)
        artifact = diff_artifact(root, scope:)
        return Master::Result.ok("critique: no changes to review") if artifact.strip.empty?
        return Master::Result.err("critique: deliberation unavailable", category: :infrastructure) unless deliberation

        bus&.publish("council:start", scope:, bytes: artifact.bytesize)
        result = deliberation.review(artifact, context: "pre-ship council gate (#{scope})")
        if result.err?
          bus&.publish("council:veto", message: result.message.to_s[0, 500])
          return result
        end

        feedback = result.value!
        summary = tribunal_summary(feedback)
        bus&.publish("council:pass", jurors: feedback.size)
        Master::Result.ok(summary)
      rescue StandardError => e
        Master::Result.err("critique: #{e.message}", category: :infrastructure)
      end

      def runner_for(container)
        lambda do |root:, scope: "diff"|
          run(
            root:,
            deliberation: container[:deliberation],
            scope:,
            bus: container[:bus]
          )
        end
      end

      def diff_artifact(root, scope:)
        case scope.to_s
        when "diff", ""
          git_capture(root, "diff", "HEAD")
        when "staged"
          git_capture(root, "diff", "--cached")
        else
          git_capture(root, "diff", "HEAD", "--", scope)
        end
      end

      def git_capture(root, *args)
        out, status = Open3.capture2e("git", "-C", root, *args)
        text = out.to_s
        return "" unless status.success?

        text.bytesize > MAX_DIFF_BYTES ? text.byteslice(0, MAX_DIFF_BYTES) + "\n... [truncated]" : text
      rescue StandardError
        ""
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
