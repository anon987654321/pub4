# frozen_string_literal: true

module Master
  module Rails
    class WebAssetPolicy
      ERB_EXTENSION = ".erb"
      SCSS_EXTENSION = ".scss"
      CSS_EXTENSION = ".css"
      JS_EXTENSION = ".js"
      VIEW_ROOT = "/app/views/"
      STIMULUS_ROOT = "/app/javascript/controllers/"

      Finding = Data.define(:field, :message, :severity)

      def audit(path:, source:)
        case File.extname(path)
        when ERB_EXTENSION then audit_erb(path, source)
        when SCSS_EXTENSION, CSS_EXTENSION then audit_stylesheet(source)
        when JS_EXTENSION then audit_javascript(path, source)
        else []
        end
      end

      def audit_erb(path, source)
        findings = []
        return findings unless path.include?(VIEW_ROOT)

        findings << Finding.new(:inline_style, "ERB views must not carry inline style attributes", :warning) if source.match?(/\sstyle=["']/)
        findings << Finding.new(:onclick, "ERB views must not use inline JavaScript handlers", :error) if source.match?(/\son[a-z]+=["']/)
        findings << Finding.new(:img_alt, "Images in ERB views need alt text or explicit empty alt", :error) if source.match?(/<img\s+(?![^>]*\balt=)/)
        findings << Finding.new(:csrf_form, "Forms should use Rails form helpers unless intentionally static", :warning) if source.match?(/<form\b/) && !source.include?("form_with")
        findings << Finding.new(:hardcoded_text, "Reusable ERB views should prefer t(...) for user-facing text", :info) if source.match?(/>\s*[A-Za-z][^<%]{3,}</)
        findings
      end

      def audit_stylesheet(source)
        findings = []
        findings << Finding.new(:important, "Stylesheets must not use !important; fix cascade or specificity", :warning) if source.match?(/!\s*important/)
        findings << Finding.new(:desktop_first, "Use mobile-first min-width media queries", :warning) if source.match?(/@media\s*\(\s*max-width/)
        findings << Finding.new(:import, "SCSS @import is deprecated; use @use or @forward", :warning) if source.match?(/@import\s+["']/)
        findings << Finding.new(:physical_property, "Prefer logical inline properties over left/right spacing", :info) if source.match?(/(?:margin|padding)-(?:left|right):/)
        findings << Finding.new(:layout_shift, "Avoid viewport-height locks that can jump on mobile browser chrome", :warning) if source.match?(/height:\s*100vh/)
        findings
      end

      def audit_javascript(path, source)
        findings = []
        findings << Finding.new(:runtime_fork, "Do not create a parallel particle-face runtime; extend face3d_engine.js", :error) if source.include?("particle-face")
        findings << Finding.new(:webgpu, "WebGPU must stay optional until CPU fallback is complete", :critical) if source.include?("navigator.gpu")
        findings << Finding.new(:sync_layout, "Avoid layout reads inside requestAnimationFrame loops", :warning) if source.match?(/requestAnimationFrame[\s\S]*(offsetWidth|offsetHeight|getBoundingClientRect)/)
        findings << Finding.new(:visibility, "Long-running visual loops should handle visibilitychange", :warning) if visual_loop?(source) && !source.include?("visibilitychange")
        findings << Finding.new(:stimulus_naming, "Stimulus controllers should live under app/javascript/controllers and end with _controller.js", :info) if stimulus_controller?(source) && !path.include?(STIMULUS_ROOT)
        findings
      end

      private

      def visual_loop?(source)
        source.include?("requestAnimationFrame") || source.include?("setInterval")
      end

      def stimulus_controller?(source)
        source.include?("@hotwired/stimulus") || source.match?(/extends\s+Controller/)
      end
    end
  end
end
