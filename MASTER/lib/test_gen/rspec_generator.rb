# frozen_string_literal: true
require "fileutils"
require "find"

module Master
  module TestGen
    class RSpecGenerator
      attr_reader :generated_tests
      
      def initialize(llm: nil)
        @llm = llm || Master::LLM.new
        @generated_tests = []
      end
      
      # Generate test for a violation
      def generate_test_for_violation(file, violation)
        spec_path = determine_spec_path(file)
        
        # Generate test content using LLM
        prompt = build_test_generation_prompt(file, violation)
        result = @llm.ask(prompt, tier: :code)
        
        return Result.err("Failed to generate test: #{result.error}") unless result.ok?
        
        test_code = extract_test_code(result.value)
        
        # Ensure spec directory exists
        FileUtils.mkdir_p(File.dirname(spec_path))
        
        # Append or create test file
        if File.exist?(spec_path)
          append_test_to_file(spec_path, test_code, violation)
        else
          create_test_file(spec_path, file, test_code, violation)
        end
        
        @generated_tests << {
          file: file,
          spec_path: spec_path,
          violation: violation,
          timestamp: Time.now.utc.iso8601
        }
        
        Result.ok(spec_path: spec_path, test_code: test_code)
      end
      
      # Generate tests for multiple violations
      def generate_tests(file, violations)
        results = []
        
        violations.each do |violation|
          result = generate_test_for_violation(file, violation)
          results << result
        end
        
        success_count = results.count(&:ok?)
        
        Result.ok(
          total: violations.size,
          generated: success_count,
          failed: violations.size - success_count
        )
      end
      
      # Get test coverage for violations
      def test_coverage
        # Scan for generated test comments
        coverage = {}
        
        Find.find("spec") do |path|
          next unless path.end_with?("_spec.rb")
          next if File.directory?(path)
          
          content = File.read(path)
          
          # Look for MASTER auto-generated comments
          content.scan(/# MASTER Auto-generated test.*?# Violation: (.+?) -/m) do |match|
            principle = match[0]
            coverage[principle] ||= []
            coverage[principle] << path
          end
        end
        
        coverage
      rescue Errno::ENOENT
        {}
      end
      
      private
      
      def determine_spec_path(file)
        # Convert lib/user.rb -> spec/user_spec.rb
        # Convert app/models/user.rb -> spec/models/user_spec.rb
        
        relative_path = file.sub(%r{^(lib|app)/}, "")
        base = File.basename(relative_path, ".*")
        dir = File.dirname(relative_path)
        
        if dir == "."
          "spec/#{base}_spec.rb"
        else
          "spec/#{dir}/#{base}_spec.rb"
        end
      end
      
      def build_test_generation_prompt(file, violation)
        principle = violation[:principle] || violation["principle"]
        description = violation[:description] || violation["description"]
        line = violation[:line] || violation["line"]
        
        <<~PROMPT
          Generate a failing RSpec test for this code quality violation:
          
          File: #{file}
          Line: #{line}
          Principle: #{principle}
          Violation: #{description}
          
          Requirements:
          1. The test should FAIL until the violation is fixed
          2. Include a comment explaining the violation
          3. Use clear, descriptive test names
          4. Follow RSpec best practices
          5. Add a timestamp comment
          
          Return ONLY the test code, no explanations.
          
          Example format:
          ```ruby
          # MASTER Auto-generated test
          # Violation: PRINCIPLE_VALIDATION - Missing email presence validation
          # Generated: 2026-02-04 10:30:00
          # Fix this by adding: validates :email, presence: true
          
          RSpec.describe User do
            it 'validates email presence' do
              user = User.new(email: nil)
              expect(user).to_not be_valid
              expect(user.errors[:email]).to include("can't be blank")
            end
          end
          ```
          
          Now generate the test:
        PROMPT
      end
      
      def extract_test_code(response)
        # Extract code from markdown code blocks
        if response =~ /```ruby\n(.*?)\n```/m
          $1
        elsif response =~ /```\n(.*?)\n```/m
          $1
        else
          response
        end
      end
      
      def create_test_file(spec_path, original_file, test_code, violation)
        class_name = File.basename(original_file, ".*").split("_").map(&:capitalize).join
        
        content = <<~RUBY
          # frozen_string_literal: true
          require 'spec_helper'
          
          #{test_code}
        RUBY
        
        File.write(spec_path, content)
      end
      
      def append_test_to_file(spec_path, test_code, violation)
        content = File.read(spec_path)
        
        # Remove the last 'end' and append new test
        content = content.rstrip
        if content.end_with?("end")
          content = content[0...-3].rstrip
        end
        
        content += "\n\n  #{test_code.gsub(/^/, '  ')}\nend\n"
        
        File.write(spec_path, content)
      end
    end
  end
end
