# frozen_string_literal: true

module Master
  module Fix
    class RuleLoop
      # Whether a violation may be fixed without a person: deletions and fixes
      # nobody can undo wait for one, and the scanner's confidence gate decides
      # the rest -- separate from attempting a fix (fix_strategies.rb) or
      # verifying one (fix_verification.rb).
      module AutofixPolicy
        private

        # A deleting transform runs only when a person asked this loop to fix, and
        # MASTER_AUTOFIX is what a person asking looks like from here: the
        # background convergence loop and the unattended ladder both leave it off.
        # An addition is visible in the diff it makes; a deletion is invisible to
        # anyone who does not already know what stood there.
        def deletions_allowed?
          ENV["MASTER_AUTOFIX"] == "1"
        end

        # A finding may say what undoing its fix costs (rules.yml
        # schema_metadata: reversibility, blast_radius). A fix nobody can undo, or
        # one that reaches past the file it was found in, waits for a person the
        # same way a deletion does.
        def needs_a_person?(violation)
          radius = violation[:blast_radius]
          files_touched = radius.is_a?(Hash) ? (radius["files_touched"] || radius[:files_touched]).to_i : 0
          violation[:reversibility].to_s == "impossible" || files_touched > 1
        end

        def autofix_allowed?(violation)
          if needs_a_person?(violation) && !deletions_allowed?
            @bus&.publish("rule_loop:autofix_skipped", rule: violation[:rule], reason: :needs_a_person)
            return false
          end
          return true unless @scanner.respond_to?(:should_autofix?, true)

          confidence = violation[:confidence] || violation["confidence"] || 1.0
          allowed = @scanner.__send__(:should_autofix?, violation[:rule], confidence,
                                      allow_deletions: deletions_allowed?)
          unless allowed
            @bus&.publish("rule_loop:autofix_skipped", rule: violation[:rule], confidence:)
            Master::Trace::Dmesg.status("fix0", "#{violation[:rule]} autofix skipped, confidence #{confidence}")
          end
          allowed
        end
      end
    end
  end
end
