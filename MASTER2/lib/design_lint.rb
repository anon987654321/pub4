# frozen_string_literal: true

module MASTER
  # DesignLint - Lint HTML/CSS against codified design axioms
  # Checks web UI files for compliance with design_axioms.yml
  module DesignLint
    extend self

    AXIOM_FILE = File.join(__dir__, "..", "data", "design_axioms.yml")

    def lint(path)
      return Result.err("File not found: #{path}") unless File.exist?(path)

      content = File.read(path)
      violations = []

      # Color token enforcement
      raw_hex = content.scan(/#[0-9a-fA-F]{3,8}/).reject { |h| h.match?(/var\(/) }
      # Allow hex inside :root block
      root_block = content[/:root\s*\{[^}]+\}/m] || ""
      raw_hex.each do |hex|
        unless root_block.include?(hex)
          violations << { rule: "color:tokens", severity: :medium,
                         message: "Raw hex #{hex} outside :root — use CSS custom property" }
        end
      end

      # setInterval check
      if content.include?("setInterval") && path.end_with?(".html")
        violations << { rule: "performance:no_setinterval", severity: :high,
                       message: "setInterval found — use requestAnimationFrame" }
      end

      # clearRect check in orb files
      if path.include?("orb_") && content.include?("clearRect")
        violations << { rule: "persistence:no_clearrect", severity: :medium,
                       message: "clearRect found — use multiplicative decay fill" }
      end

      # Focus outline-offset check
      if content.include?("outline-offset")
        violations << { rule: "accessibility:focus_ring", severity: :medium,
                       message: "outline-offset found — use box-shadow for focus rings" }
      end

      # Web font check
      if content.match?(/font-face|googleapis\.com\/css|fonts\.gstatic/)
        violations << { rule: "typography:system_only", severity: :high,
                       message: "Web font loading detected — use system monospace only" }
      end

      # Dialog check for help panels
      if content.include?('id="help"') && !content.include?("<dialog")
        violations << { rule: "accessibility:dialog", severity: :low,
                       message: "Help panel should use <dialog> element" }
      end

      # prefers-reduced-motion check for animation files
      if path.include?("orb_") && !content.include?("prefers-reduced-motion")
        violations << { rule: "accessibility:reduced_motion", severity: :medium,
                       message: "Missing prefers-reduced-motion media query" }
      end

      Result.ok(path: path, violations: violations, clean: violations.empty?)
    end

    def lint_all_views
      views_dir = File.join(__dir__, "views")
      return Result.err("Views directory not found") unless Dir.exist?(views_dir)

      results = Dir.glob(File.join(views_dir, "*.html")).map { |f| lint(f) }
      total = results.sum { |r| r.ok? ? r.value[:violations].size : 0 }
      clean = results.all? { |r| r.ok? && r.value[:clean] }

      Result.ok(files: results.size, violations: total, clean: clean, results: results)
    end
  end
end
