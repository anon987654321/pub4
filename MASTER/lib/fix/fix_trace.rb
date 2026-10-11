# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../io/exec"
require_relative "run_journal"
require_relative "transcript"
require_relative "../trace/dmesg"

module Master
  module Fix
    # What /fix says while it works: one Dmesg line per council pick and per
    # model fix, written to stdout so the parent's run_stream forwards them,
    # and a full NDJSON record of each beside it (Transcript). The lines
    # are always on; MASTER_FIX_VERBOSE=1 adds a short diff under a fix.
    module FixTrace
      PICK_CHARS = 200
      DIFF_LINES = 30
      PATCH_LINES = 2000

      module_function

      def verbose? = ENV["MASTER_FIX_VERBOSE"] == "1"

      def say(unit, text)
        Master::Trace::Dmesg.status(unit, text.to_s.gsub(/\s+/, " ").strip)
      end

      # The run journal's id, so the transcript directory matches fix_runs.json.
      def run_id
        id = ENV["MASTER_FIX_RUN_ID"].to_s
        return id unless id.empty?

        journal_run_id || (@adhoc_id ||= "adhoc-#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}-#{Process.pid}")
      end

      def journal_run_id
        roots.each do |root|
          path = File.join(root, RunJournal::PATH)
          next unless File.file?(path)

          run = JSON.parse(File.read(path)).fetch("runs", []).reverse.find { |row| row["state"] == "active" }
          return run["id"] if run
        end
        nil
      rescue StandardError
        nil
      end

      # The worktree a /fix child runs in is deleted when it finishes, so the
      # transcript lives in the main checkout the worktree was cut from.
      def roots
        [transcript_root, code_root].uniq
      end

      def code_root = File.expand_path("../..", __dir__)

      def transcript_root
        return ENV["MASTER_FIX_TRANSCRIPT_ROOT"] unless ENV["MASTER_FIX_TRANSCRIPT_ROOT"].to_s.empty?

        @transcript_root ||= begin
          out, status = Master::Io::Exec.capture2e("git", "-C", code_root, "rev-parse", "--path-format=absolute", "--git-common-dir")
          status.success? ? File.join(File.dirname(out.strip), "MASTER") : code_root
        rescue StandardError
          code_root
        end
      end

      def transcript
        id = run_id
        @transcript = Transcript.new(root: transcript_root, run_id: id) unless @transcript && @transcript_id == id
        @transcript_id = id
        @transcript
      end

      def reset!
        @transcript = nil
        @transcript_id = nil
        @transcript_root = nil
        @adhoc_id = nil
        Thread.current[:fix_trace_attempt] = nil
      end

      # A suite drives LawLoop against the real checkout; its attempts are not
      # a /fix run, so they leave no transcript unless a test names a root.
      def record(name, kind, data)
        return false if ENV["MASTER_IN_PROOF"] == "1" && ENV["MASTER_FIX_TRANSCRIPT_ROOT"].to_s.empty?

        transcript.append(name, { kind: kind.to_s }.merge(data))
      end

      # --- council critique -------------------------------------------------

      # Logs one summary line for a council round and keeps its prompt, images
      # and raw reply. Returns the Result untouched.
      def round(result, captures:, images:, context:)
        return result unless result.respond_to?(:value!)

        names = Array(images).map { |image| image[:name] }
        surfaces = Array(captures).map { |c| c[:surface].respond_to?(:id) ? c[:surface].id : c[:surface] }
        if result.respond_to?(:err?) && result.err?
          say("crit0", "council round failed, #{surfaces.size} surfaces, #{names.size} images: #{result.message.to_s[0, PICK_CHARS]}")
          record("critique", :round, surfaces:, images: names, prompt: context.to_s, error: result.message.to_s)
          return result
        end
        value = result.value!
        picks = Array(value[:cherry_picks])
        say("crit0", "council round, #{surfaces.size} surfaces, #{names.size} images, #{Array(value[:issues]).size} findings, #{picks.size} picks#{" (inconclusive)" if value[:status].to_s == "inconclusive"}")
        record("critique", :round, surfaces:, images: names, prompt: context.to_s, raw_reply: value[:feedback], issues: value[:issues], picks:, status: value[:status])
        result
      end

      PICK_FIELDS = {
        "surface" => ->(pick) { pick[VisualPass::SURFACE_RE, 1]&.strip },
        "viewport" => ->(pick) { pick[VisualPass::VIEWPORT_RE, 1]&.strip },
        "anchor" => ->(pick) { pick[VisualPass::SELECTOR_RE] || pick[VisualPass::TEXT_ANCHOR_RE, 1]&.strip },
      }.freeze

      # Logs one council pick and why it did or did not anchor to source.
      # `finding` is what VisualPass built from it, or nil. Returns `finding`.
      def pick(pick, finding, sources, anchors)
        fields = PICK_FIELDS.transform_values { |parse| parse.call(pick) }
        laws = pick[VisualPass::LAW_RE, 1]&.split(/[,\s]+/)&.map(&:strip)&.reject(&:empty?).to_a
        known = laws.select { |id| VisualUsability.ids.include?(id) }
        reason = finding ? nil : unanchored_reason(fields, known, pick, sources, anchors)
        head = "pick laws=#{known.join(",").then { |ids| ids.empty? ? "none" : ids }} #{fields["surface"] || "?"}/#{fields["viewport"] || "?"} anchor=#{fields["anchor"] || "none"}"
        head += reason ? " unanchored (#{reason})" : " anchored #{finding[:file]}:#{finding[:line]}"
        say("crit0", "#{head}: #{pick.to_s.gsub(/\s+/, " ").strip[0, PICK_CHARS]}")
        record("critique", :pick, pick:, fields:, laws: known, anchored: !finding.nil?, reason:, file: finding && finding[:file], line: finding && finding[:line])
        finding
      end

      def unanchored_reason(fields, laws, pick, sources, anchors)
        return "no surface" unless fields["surface"]
        return "no viewport" unless fields["viewport"]
        return "no selector or text anchor" unless fields["anchor"]
        return "no known visual law id" if laws.empty?

        selector = pick[VisualPass::SELECTOR_RE]
        return "selector #{selector} has no source file" if selector && !anchors[selector] && !pick[VisualPass::TEXT_ANCHOR_RE, 1]
        return "anchor file is outside the reviewed sources" if selector && anchors[selector] && !Array(sources).include?(anchors[selector])

        "anchor text not found in reviewed sources"
      end

      # --- model fixes ------------------------------------------------------

      def attempt = Thread.current[:fix_trace_attempt] ||= { prompts: [], replies: [] }

      # A new violation starts a new attempt; an unfinished one is a model that
      # never proposed anything, and is recorded as such.
      def begin_attempt(law, file)
        pending = Thread.current[:fix_trace_attempt]
        record("fixes", :attempt, pending.merge(outcome: "no_proposal")) if pending && !pending[:done] && pending[:law]
        Thread.current[:fix_trace_attempt] = { law: law.to_s, file: file.to_s, prompts: [], replies: [] }
        nil
      end

      def prompt(text)
        attempt[:prompts] << text.to_s
        text
      end

      def reply(text)
        attempt[:replies] << text.to_s
        text
      end

      def proposed(law, file, new_src)
        old_src = File.file?(file) ? File.read(file, encoding: "UTF-8") : ""
        diff = diff_of(old_src, new_src)
        added = diff.count { |l| l.start_with?("+") && !l.start_with?("+++") }
        removed = diff.count { |l| l.start_with?("-") && !l.start_with?("---") }
        attempt.merge!(law: law.to_s, file: file.to_s, patch: diff.first(PATCH_LINES).join, added:, removed:)
        say("fix0", "#{law} #{File.basename(file.to_s)} proposed +#{added} -#{removed}")
        diff.first(DIFF_LINES).each { |line| say("fix0", "  #{line.chomp}") } if verbose?
        nil
      rescue StandardError
        nil
      end

      def accepted(law, file) = finish(law, file, "accepted", nil)

      def rejected(law, file, reason)
        finish(law, file, "rejected: #{reason}", reason)
        true
      end

      def finish(law, file, outcome, reason)
        state = attempt
        state[:done] = true
        say("fix0", "#{law} #{File.basename(file.to_s)} #{outcome}")
        record("fixes", :attempt, state.except(:done).merge(law: law.to_s, file: file.to_s, outcome:, reason:))
        Thread.current[:fix_trace_attempt] = nil
        nil
      end

      def diff_of(old_src, new_src)
        return [] if old_src == new_src

        Dir.mktmpdir("fixtrace") do |dir|
          before = File.join(dir, "before")
          after = File.join(dir, "after")
          File.write(before, old_src)
          File.write(after, new_src)
          out, = Master::Io::Exec.capture2e("git", "diff", "--no-index", "--no-color", "-U2", before, after)
          out.lines.drop_while { |line| !line.start_with?("@@") }
        end
      end
    end
  end
end
