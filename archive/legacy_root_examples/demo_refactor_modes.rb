#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script to showcase refactor command modes
# This demonstrates the new --preview, --raw, and --apply modes

require_relative "../MASTER2/lib/diff_view"

puts "Refactor Command Demo"
puts "=" * 50
puts

# Create a sample file
sample_file = "/tmp/demo_refactor.rb"
original_content = <<~RUBY
  # frozen_string_literal: true
  
  class Calculator
    def add(x, y)
      x + y
    end
    
    def subtract(x, y)
      x - y
    end
  end
RUBY

File.write(sample_file, original_content)
puts "Created sample file: #{sample_file}"
puts

# Simulate refactor with --preview mode (default)
puts "1. Preview Mode (default)"
puts "-" * 50
modified_content = original_content.gsub("add", "sum").gsub("subtract", "difference")
diff = MASTER::DiffView.unified_diff(original_content, modified_content, filename: "demo_refactor.rb")
puts diff
puts

# Show --raw mode output
puts "2. Raw Mode (--raw)"
puts "-" * 50
puts modified_content
puts

# Show --apply mode (without actually applying)
puts "3. Apply Mode (--apply)"
puts "-" * 50
puts diff
puts "  Apply these changes? [y/N] _"
puts "  (In real usage, you'd type 'y' to apply or 'n' to cancel)"
puts

puts "Demo complete!"
puts "To use in real scenarios:"
puts "  refactor path/to/file.rb              # Preview diff (default)"
puts "  refactor path/to/file.rb --raw        # Show full proposed code"
puts "  refactor path/to/file.rb --apply      # Apply with confirmation"
puts

# Cleanup
File.delete(sample_file) if File.exist?(sample_file)
