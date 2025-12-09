#!/usr/bin/env ruby
# Minimal test - just create a file

File.write("test_output.txt", "✓ Ruby works at #{Time.now}\n")
puts "✓ Created test_output.txt"
