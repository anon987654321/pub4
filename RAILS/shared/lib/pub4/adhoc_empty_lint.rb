# frozen_string_literal: true

module Pub4
  # Ratchet for free-form empty copy that never uses shared/empty_state.
  # Catches "No X yet" / "Nothing here" paragraphs without a following CTA link
  # in the same ERB block (best-effort). Prefer shared empty_state for new UI.
  module AdhocEmptyLint
    # Lines that look like empty messaging without the shared partial.
    PATTERN = /
      <p[^>]*class=["'][^"']*\bdim\b[^"']*["'][^>]*>\s*
      (?:No\s+[\w\s]{2,40}|Nothing\s+(?:here|available|yet)|Ingen\s+[\w\s]{2,40})
    /ix

    OPT_OUT = "adhoc_empty: ok"
    BASELINE = 0

    Finding = Struct.new(:file, :line)

    module_function

    def run
      findings = scan
      puts "adhoc_empty_lint: #{findings.size} free-form empty line#{'s' unless findings.size == 1} " \
           "(baseline #{BASELINE})"
      findings.first(20).each { |f| puts "  #{f.file}:#{f.line}" }
      puts "  …" if findings.size > 20

      if findings.size > BASELINE
        warn "adhoc_empty_lint: count exceeded baseline — use shared/empty_state or mark #{OPT_OUT}"
        false
      else
        true
      end
    end

    def rails_root
      File.expand_path("../../..", __dir__)
    end

    def scan
      findings = []
      Dir.glob(File.join(rails_root, "*/app/views/**/*.erb")).each do |path|
        lines = File.readlines(path, encoding: "UTF-8")
        lines.each_with_index do |line, i|
          next unless line.match?(PATTERN)
          window = lines[[ i - 1, 0 ].max..[ i + 2, lines.size - 1 ].min].join
          next if window.include?(OPT_OUT)
          next if window.include?("empty_state")
          next if window.include?("link_to") || window.include?("href=")

          rel = path.sub("#{rails_root}/", "")
          findings << Finding.new(rel, i + 1)
        end
      end
      findings
    end
  end
end

exit(Pub4::AdhocEmptyLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
