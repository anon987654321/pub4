# frozen_string_literal: true

module Backlog
  # The classification vocabulary: a row's kind and tree come from the item's
  # own words, weighed by where they sit. A deliberate retuning of the rules
  # belongs here, not in the output file.
  module Classify
    # Only rows an operator owns outright. The mark is explicit: an
    # operator-action note on the row, or a heading that says the same. Prose
    # that merely mentions an operator decision ("when an operator decision
    # blocks progress") describes work for someone else and stays work.
    OPERATOR_ONLY = [
      %r{\boperator action\b}i,
      %r{\(operator\)}i,
      %r{\bthe operator decides\b}i,
      # The consolidated register marks its operator seams by heading, not
      # per-row notes: "8.5 Operator-only and external evidence seams".
      %r{\boperator[-_]only\b}i,
    ].freeze

    # Rows that open a choice rather than name work.
    PRODUCT = [
      %r{\A\*?decide\b}i,
      %r{\bdecide (?:between|whether)\b}i,
      %r{\bproduct decision\b}i,
    ].freeze

    # Rows whose whole body is evidence-gathering or re-measurement. The verb
    # may sit behind the row's own subject label ("Radio Bergen: confirm ...").
    VERIFY_VERB = %r{
      \A\*?(?:re-?run|re-?ran|run|verify|execute|measure|re-?measure|
      refresh|prove|confirm|triage|nightly)\b
    }ix.freeze
    VERIFY_LABEL = %r{\A[^:.]{2,40}:\s+}
    VERIFY_MARK = %r{\bNOT_RUN\b}
    VERIFY_SECTION = %r{\bVerification run\b}

    # Rows that measure or judge a rendered surface rather than edit code.
    DESIGN_SECTIONS = %w[Seeing Measuring Judging Editing Taste].freeze
    DESIGN_TEXTS = [
      %r{design}, %r{screenshot}, %r{captur}, %r{contrast}, %r{spacing},
      %r{type scale}, %r{typograph}, %r{\btaste\b}, %r{critique}, %r{judg},
      %r{layout}, %r{overlay}, %r{contact sheet}, %r{aesthetic},
      %r{tap target}, %r{\bcolour\b}, %r{\bcolor\b}, %r{accessib},
      %r{serif|brutalist},
      %r{visual (?:sweep|proof|review|evidence|baseline|completion|identit)},
    ].freeze

    TREE_SIGNALS = {
      "MASTER" => [
        %r{\bMASTER\b}, %r{/fix}, %r{\bCLI\b}, %r{\bTTS\b}, %r{\bface\b},
        %r{\blaws?\.yml\b}, %r{\bchecks?\b}i, %r{\blib/}, %r{\bdata/},
        %r{\bmission\b}i, %r{\bbacklog\b}i, %r{\bdmesg\b}i, %r{\blaw\b}i
      ],
      "RAILS" => [
        %r{\bRAILS\b}, %r{\bbrgen\b}i, %r{\bamber\b}i, %r{\bbsdports\b}i,
        %r{\bmrdamascy\b}i, %r{\bRails\b}, %r{\bERB\b}, %r{\bSCSS\b}i,
        %r{\bStimulus\b}, %r{\bTurbo\b}, %r{\bPWA\b}i, %r{\bengines?\b}i,
        %r{\broutes?\b}i, %r{\bapps?\b}i,
        %r{\bmarketplace|takeaway|dating|messenger|playlist|maps|storefront\b}i
      ],
      "OPENBSD" => [
        %r{\bOpenBSD\b}i, %r{\bvm23\b}, %r{\brelayd\b}, %r{\bhttpd\b},
        %r{\brc\.d\b}, %r{\bswap\b}i, %r{\bdeploy}i, %r{\bVPS\b},
        %r{\bpfctl\b}, %r{\blogin\.conf\b}, %r{\bcron\b}i
      ],
      "STUDIO" => [
        %r{\bSTUDIO\b}, %r{\bdilla\b}i, %r{\bpostpro\b}i, %r{\baudio\b}i,
        %r{\bvisualiz}i, %r{\bmusic\b}i,
      ],
    }.freeze

    module_function

    def kind(item:, text:, section:)
      return "plan" if item[:plan]
      return "design" if DESIGN_SECTIONS.include?(item[:h3]) || DESIGN_SECTIONS.include?(item[:h2])
      return "operator-only" if operator_row?(text, section)
      return "product" if PRODUCT.any? { |pattern| text.match?(pattern) }
      return "verify" if verify_row?(text, section)
      return "design" if DESIGN_TEXTS.any? { |pattern| text.match?(pattern) }

      "mechanical"
    end

    def signal_counts(text, section)
      TREE_SIGNALS.transform_values do |patterns|
        patterns.sum { |pattern| (section.scan(pattern).size * 2) + text.scan(pattern).size }
      end
    end

    def operator_row?(text, section)
      OPERATOR_ONLY.any? { |pattern| text.match?(pattern) || section.match?(pattern) }
    end

    def verify_row?(text, section)
      text.match?(VERIFY_VERB) || text.match?(VERIFY_MARK) ||
        section.match?(VERIFY_SECTION) || text.sub(VERIFY_LABEL, "").match?(VERIFY_VERB)
    end
  end
end
