# frozen_string_literal: true

module Pub4
  # Flags shared/empty_state renders that skip the action:/actions: local the
  # partial already supports -- a rendered empty state with no next step is
  # a dead end (NO_DEAD_ENDS / rams_checklist.thorough), and 47 of 54 call
  # sites had exactly this gap when first audited 2026-07-21.
  #
  # This is a ratchet, not a hard bar: existing gaps don't block CI today
  # (fixing each needs a real, contextual CTA, not a bulk edit), but the
  # count can never silently grow. Add `<%# empty_state: no-action-ok %>`
  # immediately above a call site to mark it deliberately CTA-less.
  # BASELINE = the exact count this scanner found on 2026-07-21; lower it
  # as gaps get fixed, never raise it to make a failing run pass.
  module EmptyStateLint
    RENDER_CALL = /render\s*\(?\s*(?:partial:\s*)?["']shared\/empty_state["'].*?%>/m
    OPT_OUT = "empty_state: no-action-ok"
    # Ratchet ceiling: raise only when a specific new gap is a deliberate,
    # reviewed decision -- never bump this just to make a failing run pass.
    # Zero gaps as of 2026-07-31 residual vertical empty-state CTA pass.
    # Deliberate no-CTA sites use `<%# empty_state: no-action-ok %>`.
    # Never raise to silence a new gap.
    BASELINE = 0

    Finding = Struct.new(:file, :line)

    module_function

    def run
      findings = scan
      puts "empty_state_lint: #{findings.size} render#{'s' unless findings.size == 1} without action:/actions: " \
           "(baseline #{BASELINE})"
      findings.each { |f| puts "  #{f.file}:#{f.line}" }

      if findings.size > BASELINE
        warn "empty_state_lint: #{findings.size} exceeds the baseline of #{BASELINE} -- new empty states need a real action: CTA"
        false
      else
        true
      end
    end

    def rails_root
      File.expand_path("../../..", __dir__) # RAILS/
    end

    def relative(path)
      path.sub("#{rails_root}/", "")
    end

    def view_files
      Dir.glob(File.join(rails_root, "*/app/views/**/*.erb"))
    end

    def scan
      findings = []
      view_files.each do |path|
        content = File.read(path, encoding: "UTF-8")
        content.to_enum(:scan, RENDER_CALL).each do
          match = Regexp.last_match
          call = match[0]
          next if call.include?("action:") || call.include?("actions:")

          line = content[0...match.begin(0)].count("\n") + 1
          preceding = content.lines[0...(line - 1)].last(2).join
          next if preceding.include?(OPT_OUT)

          findings << Finding.new(relative(path), line)
        end
      end
      findings
    end
  end
end

exit(Pub4::EmptyStateLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
