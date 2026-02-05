# frozen_string_literal: true

module MASTER
  # Auto-apply relevant principles based on detected file type
  class PrincipleAutoloader
    # File type to principle mapping
    FILE_PRINCIPLES = {
      ruby: %w[
        01-kiss 02-dry 05-single-responsibility 10-law-of-demeter
        12-fail-fast 21-explicit-over-implicit 25-meaningful-names
        26-small-functions 29-immutability 30-pure-functions
      ],
      javascript: %w[
        01-kiss 02-dry 05-single-responsibility 12-fail-fast
        21-explicit-over-implicit 25-meaningful-names 26-small-functions
        29-immutability 30-pure-functions
      ],
      rails: %w[
        01-kiss 02-dry 05-single-responsibility 14-command-query-separation
        22-convention-over-configuration
      ],
      frontend: %w[
        01-kiss 15-wcag-accessibility 31-graceful-degradation
        32-progressive-enhancement 33-mobile-first
      ],
      security: %w[
        10-validate-all-input 41-security-by-default
        42-principle-of-least-privilege
      ],
      api: %w[
        01-kiss 02-dry 12-fail-fast 13-explicit-over-implicit
        18-idempotent-operations
      ]
    }.freeze
    
    # Context-based principle selection
    CONTEXT_PRINCIPLES = {
      refactoring: %w[02-dry 05-single-responsibility 15-boy-scout-rule],
      new_feature: %w[01-kiss 12-fail-fast 05-single-responsibility],
      bug_fix: %w[12-fail-fast 19-defensive-programming],
      optimization: %w[26-optimize-last 27-measure-first 32-cache-aggressively],
      documentation: %w[28-document-why-not-what 34-prose-over-lists]
    }.freeze
    
    class << self
      # Auto-load principles for file
      def load_for_file(file_path)
        file_type = detect_file_type(file_path)
        principles = FILE_PRINCIPLES[file_type] || []
        
        load_principles(principles)
      end
      
      # Auto-load principles for context
      def load_for_context(context)
        principles = CONTEXT_PRINCIPLES[context] || []
        load_principles(principles)
      end
      
      # Load principles by names
      def load_principles(principle_names)
        principle_names.map do |name|
          Principle.load(name)
        end.compact
      end
      
      # Get recommended principles for file
      def recommend_for_file(file_path)
        file_type = detect_file_type(file_path)
        FILE_PRINCIPLES[file_type] || []
      end
      
      # Get recommended principles for context
      def recommend_for_context(context)
        CONTEXT_PRINCIPLES[context] || []
      end
      
      # Detect file type from path
      def detect_file_type(file_path)
        case file_path
        when /\.rb$/
          :ruby
        when /\.js$/, /\.jsx$/
          :javascript
        when /\/controllers\//, /\/models\//, /\/views\//
          :rails
        when /\.html/, /\.css/, /\.scss/
          :frontend
        when /security/, /auth/, /crypto/
          :security
        when /\/api\//, /\/controllers\/api\//
          :api
        else
          :general
        end
      end
      
      # Apply principles to code analysis
      def apply_to_code(code, file_path)
        principles = load_for_file(file_path)
        violations = []
        
        principles.each do |principle|
          # Check for anti-patterns
          anti_patterns = principle[:anti_patterns] || []
          anti_patterns.each do |pattern|
            if code.match?(Regexp.new(pattern, Regexp::IGNORECASE))
              violations << {
                principle: principle[:name],
                pattern: pattern,
                severity: :medium
              }
            end
          end
        end
        
        violations
      end
      
      # Get all principles grouped by category
      def all_by_category
        {
          design: %w[01-kiss 02-dry 03-yagni 04-separation-of-concerns],
          solid: %w[05-single-responsibility 06-open-closed 07-liskov-substitution
                   08-interface-segregation 09-dependency-inversion],
          quality: %w[10-law-of-demeter 11-composition-over-inheritance 12-fail-fast
                     13-principle-of-least-astonishment 14-command-query-separation],
          code: %w[21-explicit-over-implicit 25-meaningful-names 26-small-functions
                  29-immutability 30-pure-functions],
          architecture: %w[16-unix-philosophy 17-functional-core-imperative-shell
                          22-convention-over-configuration]
        }
      end
    end
  end
end
