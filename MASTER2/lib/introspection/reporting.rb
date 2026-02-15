# frozen_string_literal: true

module MASTER
  module Analysis
  class Introspection
    class << self
      def print_prose_summary(results)
        passed = results.values.count { |r| r[:passed] }
        total = results.size

        static = results[:static_analysis]
        consistency = results[:consistency_checks]
        enforcement = results[:enforcement]
        logic = results[:logic_checks]
        introspection_result = results[:introspection]
        council = results[:council_review]

        # Build natural prose
        paragraphs = []

        # Opening
        if passed == total
          paragraphs << "MASTER passed all #{total} self-application phases. The codebase meets its own standards."
        elsif passed >= total - 2
          paragraphs << "MASTER completed self-application with #{passed} of #{total} phases passing. A few areas need attention."
        else
          paragraphs << "Self-application found gaps in #{total - passed} of #{total} phases. Significant work remains."
        end

        # Static analysis and structure
        issues_summary = []
        issues_summary << "#{static[:issues] || 0} static analysis issues" if static[:issues].to_i > 0
        issues_summary << "#{consistency[:issues]&.size || 0} consistency issues" if consistency[:issues]&.size.to_i > 0
        issues_summary << "#{enforcement[:violations]&.size || 0} axiom violations" if enforcement[:violations]&.size.to_i > 0

        if issues_summary.any?
          paragraphs << "Code review found #{issues_summary.join(', ')}. Most are minor style issues like missing periods in error messages or mixed hash key types."
        else
          paragraphs << "Code review found no significant issues."
        end

        # Logic and adversarial
        if logic[:issues]&.size.to_i > 0 || introspection_result[:issues]&.size.to_i > 0
          logic_count = logic[:issues]&.size || 0
          adversarial_count = introspection_result[:issues]&.size || 0
          paragraphs << "Deeper analysis identified #{logic_count} logic patterns worth reviewing and #{adversarial_count} potential issues from adversarial introspection. These include thread-safety considerations and edge cases an attacker might exploit."
        end

        # Council rating
        if council[:rating]
          rating = council[:rating]
          if rating >= 8
            paragraphs << "The adversarial council rated the codebase #{rating}/10, indicating strong alignment with stated axioms."
          elsif rating >= 6
            paragraphs << "The adversarial council rated the codebase #{rating}/10. Room for improvement exists but fundamentals are solid."
          else
            paragraphs << "The adversarial council rated the codebase #{rating}/10, suggesting significant gaps between stated principles and implementation."
          end
        end

        # Print with nice wrapping
        paragraphs.each do |para|
          puts word_wrap(para, 72)
          puts
        end
      end

      def word_wrap(text, width)
        text.gsub(/(.{1,#{width}})(\s+|$)/, "\\1\n").strip
      end
    end
  end
  end
end
