# frozen_string_literal: true

require_relative "../trace/dmesg"

module Master
  module Fix
    # The findings one file repair proposes a fix for. FileRepair asked for every finding a file held in
    # one prompt, so a 2,800-line stylesheet became one proposal for MOBILE_FIRST, NO_ASCII_LINE_ART,
    # SMALL_FILES, LINE_HEIGHT_ON_SCALE and TOUCH_TARGET_MIN at once, its diff spanning the file; the
    # verifier refused 5 of the 7 RAILS proposals of the 2026-11-05 run, the big ones.
    #
    # A proposal now takes the findings inside one scope window (WINDOW lines from the first), the
    # window holding the most of them, so adjacent findings still share one call. A whole-file finding
    # (a law whose every finding in the file sits on line 1, such as SMALL_FILES) touches the whole
    # file, so it goes alone, one law per proposal, after the windows. The findings left out wait for
    # the next pass, which scans the repaired file again.
    module ProposalScope
      # Twice FileBudget's SCOPE_PAD: a window's changes then stay inside the range its own guard allows.
      WINDOW = Integer(ENV.fetch("MASTER_FIX_SCOPE_WINDOW", "50"))

      module_function

      # [taken, deferred]: the findings this proposal takes on, and those left for a later pass.
      def narrow(findings, file: nil, window: WINDOW)
        taken = groups(findings, window:).first || []
        deferred = findings - taken
        if deferred.any? && file
          Master::Trace::Dmesg.status("fix0", "#{file}: proposing #{taken.size} finding(s) of #{laws(taken)}, " \
                                              "#{deferred.size} wait for the next pass (one scope window a proposal)")
        end
        [taken, deferred]
      end

      # Every proposal the findings make, in the order they are taken.
      def groups(findings, window: WINDOW)
        whole, located = findings.partition { |finding| whole_file?(finding, findings) }
        windows = clusters(located.sort_by { |finding| finding[:line].to_i }, window)
        ranked = windows.each_with_index.sort_by { |group, index| [-group.size, index] }.map(&:first)
        ranked + whole.group_by { |finding| finding[:law].to_s }.values
      end

      # Greedy over the findings in line order: a window opens at a finding and takes every later one
      # within WINDOW lines of it.
      def clusters(sorted, window)
        sorted.each_with_object([]) do |finding, out|
          start = out.last&.first
          if start && finding[:line].to_i - start[:line].to_i <= window
            out.last << finding
          else
            out << [finding]
          end
        end
      end

      def whole_file?(finding, findings)
        law = finding[:law].to_s
        findings.select { |other| other[:law].to_s == law }.all? { |other| other[:line].to_i <= 1 }
      end

      def laws(findings) = findings.map { |finding| finding[:law].to_s }.uniq.join("+")
    end
  end
end
