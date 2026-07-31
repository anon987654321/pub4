# frozen_string_literal: true

module Pub4
  # Ratchet: empty-state titles and live-search placeholders must go through
  # I18n (t(...)), not hardcoded English. Default locale is :nb across the
  # family — raw "No …" / "Search …" re-introduces EN chrome on every surface.
  #
  # Mirrors empty_state_lint: baseline 0, never raise to silence new debt.
  # Opt out a deliberate EN-only string with: <%# chrome_i18n: ok %>
  #
  # MASTER playbook: design_rules.yml#ui_polish + surface_rules ERB_HARDCODED_CHROME.
  module ChromeI18nLint
    # title: "No …" / title: "Nothing …" without t(
    EMPTY_TITLE = /
      title:\s*
      (?:
        "(?:No\s|Nothing\s)[^"]{0,80}"
        |
        '(?:No\s|Nothing\s)[^']{0,80}'
      )
    /x

    # placeholder: "Search …" without t(
    SEARCH_PLACEHOLDER = /
      placeholder:\s*
      (?:
        "Search[^"]{0,80}"
        |
        'Search[^']{0,80}'
      )
    /x

    OPT_OUT = "chrome_i18n: ok"
    BASELINE = 0

    Finding = Struct.new(:file, :line, :kind)

    module_function

    def run
      findings = scan
      puts "chrome_i18n_lint: #{findings.size} hardcoded EN chrome string#{'s' unless findings.size == 1} " \
           "(baseline #{BASELINE})"
      findings.first(30).each { |f| puts "  #{f.file}:#{f.line} [#{f.kind}]" }
      puts "  …" if findings.size > 30

      if findings.size > BASELINE
        warn "chrome_i18n_lint: exceeds baseline — use t(\"empty.*\") / t(\"search.*\") or mark #{OPT_OUT}"
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
        # Doc comment inside the partial itself is not a call site.
        next if path.end_with?("shared/_empty_state.html.erb")

        lines = File.readlines(path, encoding: "UTF-8")
        lines.each_with_index do |line, i|
          next if line.include?("t(") || line.include?("I18n.t")
          next if comment_or_opt_out?(lines, i)

          if line.match?(EMPTY_TITLE)
            findings << Finding.new(rel(path), i + 1, "empty_title")
          elsif line.match?(SEARCH_PLACEHOLDER)
            findings << Finding.new(rel(path), i + 1, "search_placeholder")
          end
        end
      end
      findings
    end

    def rel(path)
      path.sub("#{rails_root}/", "")
    end

    def comment_or_opt_out?(lines, index)
      window = lines[[index - 1, 0].max..index].join
      window.include?(OPT_OUT) || window.lstrip.start_with?("<%#", "#")
    end
  end
end

exit(Pub4::ChromeI18nLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
