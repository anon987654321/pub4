#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'

# Load configuration from master.json
CONFIG = JSON.parse(File.read(File.join(Dir.pwd, 'master.json')))

# Helper to navigate nested config
def cfg(*keys)
  keys.reduce(CONFIG) { |hash, key| hash&.dig(key.to_s) }
end

# Simple terminal spinner
class Spinner
  FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
  
  def initialize(message)
    @message = message
    @running = false
    @thread = nil
  end
  
  def start
    @running = true
    @thread = Thread.new do
      idx = 0
      while @running
        print "\r#{FRAMES[idx % FRAMES.length]} #{@message}"
        sleep 0.1
        idx += 1
      end
      print "\r"
    end
  end
  
  def stop(final_message = nil)
    @running = false
    @thread&.join
    puts final_message if final_message
  end
end

# Code transformer for formatting and auditing
module CodeTransformer
  extend self
  
  def transform(content, ext)
    result = content.dup
    
    # (1) Simplify `if !` to `unless`
    result = simplify_negations(result) if ['rb', 'zsh', 'sh'].include?(ext)
    
    # (2) De-duplicate identical non-comment lines appearing >3 times
    result = deduplicate_lines(result)
    
    # (3) Normalize spacing unit properties
    result = normalize_spacing(result) if ['css', 'scss', 'html'].include?(ext)
    
    result
  end
  
  def simplify_negations(content)
    # Transform `if !condition` to `unless condition`
    content.gsub(/if\s+!([^\s]+)/, 'unless \1')
  end
  
  def deduplicate_lines(content)
    lines = content.lines
    threshold = cfg('policy', 'dedup_threshold') || 3
    
    # Count non-comment, non-empty lines
    line_counts = Hash.new(0)
    lines.each do |line|
      stripped = line.strip
      next if stripped.empty? || stripped.start_with?('#', '//', '/*', '*', '--')
      line_counts[stripped] += 1
    end
    
    # Find duplicated lines
    duplicated = line_counts.select { |_, count| count > threshold }.keys
    
    if duplicated.any?
      # Keep only the first occurrence of each duplicated line
      seen = Hash.new(0)
      lines = lines.map do |line|
        stripped = line.strip
        if duplicated.include?(stripped)
          seen[stripped] += 1
          seen[stripped] == 1 ? line : nil
        else
          line
        end
      end.compact
      
      lines.join
    else
      content
    end
  end
  
  def normalize_spacing(content)
    scale = cfg('policy', 'spacing_scale') || [0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64]
    
    # Match spacing properties (gap, padding, margin, border-spacing)
    content.gsub(/\b(gap|padding|margin|border-spacing):\s*(\d+)px\b/) do |match|
      property = $1
      value = $2.to_i
      
      # Find nearest value in scale
      nearest = scale.min_by { |s| (s - value).abs }
      
      "#{property}: #{nearest}px"
    end
  end
  
  def audit(content, filepath)
    issues = []
    ext = File.extname(filepath)[1..]
    
    # Check for forbidden ternary
    if cfg('policy', 'forbid_ternary')
      content.lines.each_with_index do |line, idx|
        if line.match?(/\?.*:/)
          issues << "Line #{idx + 1}: Ternary operator forbidden"
        end
      end
    end
    
    # Check max line length
    max_length = cfg('policy', 'max_line_length') || 120
    content.lines.each_with_index do |line, idx|
      if line.chomp.length > max_length
        issues << "Line #{idx + 1}: Exceeds max length (#{line.chomp.length} > #{max_length})"
      end
    end
    
    # Check WCAG contrast (simplified - just look for color patterns)
    if ['css', 'scss', 'html'].include?(ext)
      min_ratio = cfg('design_system', 'contrast_min_ratio') || 4.5
      # This is a simplified check - real contrast calculation would be more complex
      if content.match?(/#[0-9a-fA-F]{6}/) && content.match?(/color|background/)
        issues << "Note: Manual contrast check recommended (min ratio: #{min_ratio}:1)"
      end
    end
    
    issues
  end
end

# Main formatter with terminal UI
class MasterFormatter
  SKIP_DIRS = ['vendor', 'node_modules', 'tmp', '.git']
  
  def initialize
    @extensions = cfg('tools', 'file_extensions') || []
  end
  
  def run
    loop do
      puts "\n" + "=" * 60
      puts "Master Formatter & Auditor"
      puts "=" * 60
      puts "1) Format - Transform code according to rules"
      puts "2) Audit - Check code for violations"
      puts "3) Prompts - View prompt library"
      puts "4) Export - Export prompts to file"
      puts "5) Exit"
      puts "=" * 60
      print "Choose an option: "
      
      choice = gets.chomp
      
      case choice
      when '1'
        format_files
      when '2'
        audit_files
      when '3'
        view_prompts
      when '4'
        export_prompts
      when '5'
        puts "Goodbye!"
        break
      else
        puts "Invalid choice. Please try again."
      end
    end
  end
  
  def format_files
    files = find_files
    
    if files.empty?
      puts "No files found to format."
      return
    end
    
    puts "\nFound #{files.length} file(s) to format."
    
    files.each do |file|
      ext = File.extname(file)[1..]
      next unless @extensions.include?(ext)
      
      spinner = Spinner.new("Formatting #{file}")
      spinner.start
      
      begin
        content = File.read(file)
        transformed = CodeTransformer.transform(content, ext)
        
        if transformed != content
          File.write(file, transformed)
          spinner.stop("✓ Formatted #{file}")
          
          # Run external tool if configured
          run_external_tool(file, ext)
        else
          spinner.stop("- No changes needed for #{file}")
        end
      rescue => e
        spinner.stop("✗ Error formatting #{file}: #{e.message}")
      end
    end
    
    puts "\nFormatting complete!"
  end
  
  def audit_files
    files = find_files
    
    if files.empty?
      puts "No files found to audit."
      return
    end
    
    puts "\nAuditing #{files.length} file(s)..."
    total_issues = 0
    
    files.each do |file|
      ext = File.extname(file)[1..]
      next unless @extensions.include?(ext)
      
      begin
        content = File.read(file)
        issues = CodeTransformer.audit(content, file)
        
        if issues.any?
          puts "\n#{file}:"
          issues.each { |issue| puts "  - #{issue}" }
          total_issues += issues.length
        end
      rescue => e
        puts "Error auditing #{file}: #{e.message}"
      end
    end
    
    if total_issues == 0
      puts "\n✓ No issues found!"
    else
      puts "\n✗ Found #{total_issues} issue(s)."
    end
  end
  
  def view_prompts
    prompts = cfg('prompts') || {}
    
    if prompts.empty?
      puts "No prompts found in configuration."
      return
    end
    
    puts "\n" + "=" * 60
    puts "Prompt Library"
    puts "=" * 60
    
    prompts.each do |key, value|
      puts "\n[#{key}]"
      puts value
      puts "-" * 60
    end
  end
  
  def export_prompts
    prompts = cfg('prompts') || {}
    
    if prompts.empty?
      puts "No prompts to export."
      return
    end
    
    filename = "prompts_export_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt"
    
    File.open(filename, 'w') do |f|
      f.puts "Prompt Library Export"
      f.puts "=" * 60
      f.puts "Generated: #{Time.now}"
      f.puts "=" * 60
      f.puts
      
      prompts.each do |key, value|
        f.puts "[#{key}]"
        f.puts value
        f.puts
        f.puts "-" * 60
        f.puts
      end
    end
    
    puts "✓ Prompts exported to #{filename}"
  end
  
  private
  
  def find_files
    files = []
    
    Dir.glob('**/*', File::FNM_DOTMATCH).each do |path|
      next unless File.file?(path)
      next if SKIP_DIRS.any? { |dir| path.include?("/#{dir}/") || path.start_with?("#{dir}/") }
      
      ext = File.extname(path)[1..]
      files << path if @extensions.include?(ext)
    end
    
    files
  end
  
  def run_external_tool(file, ext)
    external_tools = cfg('tools', 'external_tools') || {}
    tool = external_tools[ext]
    
    return unless tool
    
    # Check if tool is available
    tool_name = tool.split.first
    return unless system("which #{tool_name} > /dev/null 2>&1")
    
    # Run the tool
    system("#{tool} #{file} > /dev/null 2>&1")
  end
end

# Main entry point
if __FILE__ == $PROGRAM_NAME
  begin
    formatter = MasterFormatter.new
    formatter.run
  rescue Interrupt
    puts "\n\nInterrupted. Goodbye!"
    exit 0
  rescue => e
    puts "Error: #{e.message}"
    puts e.backtrace.join("\n")
    exit 1
  end
end
