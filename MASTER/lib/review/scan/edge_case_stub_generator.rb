# frozen_string_literal: true

require "fileutils"

module Master
  module Review
    module Scan
      class EdgeCaseStubGenerator
        CASES = [
          ["nil input", "nil"],
          ["empty string", "\"\""],
          ["empty array", "[]"],
          ["max integer", "(2**63 - 1)"],
          ["10k-char string", "\"x\" * 10_000"],
          ["unicode", "\"Bergen ålesund 東京\""],
          ["invalid JSON", "\"{\""],
          ["truncated file", "\"partial: [\""],
          ["injection attempt", "\"'; rm -rf / #\""],
        ].freeze

        def initialize(root:)
          @root = root
        end

        def call(target)
          source = expand(target)
          return Result.err("edge-cases: missing target", category: :validation) if source.empty?

          out = test_path(source)
          FileUtils.mkdir_p(File.dirname(out))
          File.write(out, render(source), encoding: "UTF-8")
          Result.ok("edge-cases: wrote #{out.delete_prefix("#{@root}/")}")
        end

        private

        def expand(target)
          path = target.to_s.strip
          return "" if path.empty?

          File.expand_path(path, @root)
        end

        def test_path(source)
          rel = source.delete_prefix("#{@root}/").sub(%r{\Alib/}, "")
          File.join(@root, "test", "edge_cases", "test_#{rel.tr("/.", "_")}")
        end

        def render(source)
          constant = File.basename(source, ".rb").split("_").map(&:capitalize).join
          cases = CASES.map do |label, value|
            <<~RUBY
              def test_#{method_name(label)}
                skip "wire #{constant} API for #{label}"
                input = #{value}
                refute_nil input
              end
            RUBY
          end.join("\n")
          <<~RUBY
            # frozen_string_literal: true

            require_relative "../test_helper"

            class Test#{constant}EdgeCases < Minitest::Test
            #{indent(cases, 2)}
            end
          RUBY
        end

        def method_name(label)
          label.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
        end

        def indent(text, spaces)
          prefix = " " * spaces
          text.lines.map { |line| line.strip.empty? ? line : "#{prefix}#{line}" }.join
        end
      end
    end
  end
end
