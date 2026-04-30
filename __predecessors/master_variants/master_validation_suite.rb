#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'
require 'open3'
require 'yaml'

# Master.json v12.9.0 Validation Suite
class MasterValidationSuite
  def initialize
    @config = load_master_config
    @gem_path = '/home/runner/.local/share/gem/ruby/3.2.0/bin'
    @validation_results = {}
    @processed_files = []
    @failed_files = []
    @start_time = Time.now
  end

  def execute_validation
    puts '§ Master.json v12.9.0 Validation Suite Started'

    # Setup validation environment
    setup_validation_environment

    # Create validation configurations
    create_validation_configs

    # Process files by priority
    process_files_by_priority

    # Run comprehensive validation
    run_comprehensive_validation

    # Generate final report
    generate_validation_report

    puts '✅ Validation suite completed!'
  end

  private

  def load_master_config
    config_path = File.join(__dir__, 'master.json')
    JSON.parse(File.read(config_path))
  end

  def setup_validation_environment
    puts 'Setting up validation environment...'

    # Ensure gem path is available
    ENV['PATH'] = "#{@gem_path}:#{ENV.fetch('PATH', nil)}"

    # Create necessary directories
    FileUtils.mkdir_p('tmp/validation')
    FileUtils.mkdir_p('logs')

    puts '✅ Environment ready'
  end

  def create_validation_configs
    puts 'Creating validation configurations...'

    create_rubocop_config
    create_gitignore_validation

    puts '✅ Configurations created'
  end

  def create_rubocop_config
    config = {
      'AllCops' => {
        'TargetRubyVersion' => 3.2,
        'NewCops' => 'enable',
        'Exclude' => [
          '.git/**/*',
          'tmp/**/*',
          'logs/**/*',
          'vendor/**/*',
          '.bundle/**/*'
        ]
      },
      'Metrics/MethodLength' => {
        'Max' => 20,
        'CountComments' => false
      },
      'Metrics/ClassLength' => {
        'Max' => 300
      },
      'Metrics/CyclomaticComplexity' => {
        'Max' => 10
      },
      'Layout/LineLength' => {
        'Max' => 120,
        'AllowedPatterns' => ['\A\s*#']
      },
      'Style/Documentation' => {
        'Enabled' => false
      },
      'Naming/MethodName' => {
        'EnforcedStyle' => 'snake_case'
      },
      'Style/FrozenStringLiteralComment' => {
        'Enabled' => true,
        'EnforcedStyle' => 'always'
      },
      'Metrics/AbcSize' => {
        'Max' => 25
      },
      'Metrics/BlockLength' => {
        'Enabled' => false
      }
    }

    File.write('.rubocop.yml', config.to_yaml)
  end

  def create_gitignore_validation
    # Ensure .gitignore exists and includes validation artifacts
    gitignore_content = File.exist?('.gitignore') ? File.read('.gitignore') : ''

    validation_entries = [
      '# Validation artifacts',
      'tmp/validation/',
      'logs/',
      '*.log',
      'test_compliance_report.json',
      'validation_report.json',
      '.rubocop.yml'
    ]

    validation_entries.each do |entry|
      gitignore_content += "\n#{entry}" unless gitignore_content.include?(entry)
    end

    File.write('.gitignore', gitignore_content)
  end

  def process_files_by_priority
    puts 'Processing files by priority...'

    priorities = @config['file_priorities']

    %w[critical high medium low].each do |priority|
      process_priority_level(priority, priorities[priority])
    end

    puts '✅ File processing completed'
  end

  def process_priority_level(priority, patterns)
    puts "Processing #{priority} priority files..."

    files = []
    patterns.each do |pattern|
      Dir.glob(pattern).each do |file|
        next unless File.file?(file)
        next if file.start_with?('.git/')
        next if file.start_with?('tmp/')
        next if file.start_with?('logs/')

        files << {
          path: file,
          type: determine_file_type(file),
          priority: priority
        }
      end
    end

    puts "  Found #{files.size} files"

    # Process in batches to respect resource limits
    batch_size = @config['resource_limits']['batch_size']
    files.each_slice(batch_size) do |batch|
      batch.each do |file|
        process_single_file(file)
      end
    end

    puts "  ✅ #{priority} priority files processed"
  end

  def determine_file_type(path)
    case File.extname(path)
    when '.rb' then 'ruby'
    when '.js' then 'javascript'
    when '.sh' then 'shell'
    when '.md' then 'markdown'
    when '.json' then 'json'
    when '.yml', '.yaml' then 'yaml'
    else 'other'
    end
  end

  def process_single_file(file)
    @processed_files << file[:path]

    case file[:type]
    when 'ruby'
      validate_ruby_file(file)
    when 'shell'
      validate_shell_file(file)
    when 'markdown'
      validate_markdown_file(file)
    when 'json'
      validate_json_file(file)
    when 'yaml'
      validate_yaml_file(file)
    end
  end

  def validate_ruby_file(file)
    # Basic syntax check
    content = File.read(file[:path])
    RubyVM::InstructionSequence.compile(content)

    # Check for frozen string literal
    unless content.start_with?('# frozen_string_literal: true') || content.start_with?('#!/usr/bin/env ruby')
      add_frozen_string_literal(file[:path])
    end
  rescue SyntaxError => e
    @failed_files << { path: file[:path], error: "Syntax error: #{e.message}" }
  rescue StandardError => e
    @failed_files << { path: file[:path], error: "Validation error: #{e.message}" }
  end

  def validate_shell_file(file)
    content = File.read(file[:path])

    # Check for shebang
    add_shebang_to_shell(file[:path]) unless content.start_with?('#!/bin/bash') || content.start_with?('#!/bin/sh')

    # Make executable if not already
    File.chmod(0o755, file[:path]) unless File.executable?(file[:path])
  rescue StandardError => e
    @failed_files << { path: file[:path], error: "Shell validation error: #{e.message}" }
  end

  def validate_markdown_file(file)
    content = File.read(file[:path])

    # Apply Strunk & White rules - max 15 words per sentence
    apply_markdown_formatting(file[:path], content)
  rescue StandardError => e
    @failed_files << { path: file[:path], error: "Markdown validation error: #{e.message}" }
  end

  def validate_json_file(file)
    JSON.parse(File.read(file[:path]))
  rescue JSON::ParserError => e
    @failed_files << { path: file[:path], error: "JSON syntax error: #{e.message}" }
  rescue StandardError => e
    @failed_files << { path: file[:path], error: "JSON validation error: #{e.message}" }
  end

  def validate_yaml_file(file)
    YAML.safe_load_file(file[:path])
  rescue Psych::SyntaxError => e
    @failed_files << { path: file[:path], error: "YAML syntax error: #{e.message}" }
  rescue StandardError => e
    @failed_files << { path: file[:path], error: "YAML validation error: #{e.message}" }
  end

  def add_frozen_string_literal(filepath)
    content = File.read(filepath)

    # Don't add to files that already have it or are not Ruby files
    return if content.include?('frozen_string_literal: true')

    # Add frozen string literal at the top
    if content.start_with?('#!/usr/bin/env ruby')
      lines = content.lines
      shebang = lines[0]
      rest = lines[1..-1]
      new_content = "#{shebang}# frozen_string_literal: true\n\n#{rest.join}"
    else
      new_content = "# frozen_string_literal: true\n\n#{content}"
    end

    File.write(filepath, new_content)
    puts "  ✅ Added frozen string literal to #{filepath}"
  end

  def add_shebang_to_shell(filepath)
    content = File.read(filepath)

    # Add bash shebang if missing
    new_content = "#!/bin/bash\n\n#{content}"
    File.write(filepath, new_content)
    puts "  ✅ Added shebang to #{filepath}"
  end

  def apply_markdown_formatting(filepath, content)
    lines = content.split("\n")
    modified = false

    formatted_lines = lines.map do |line|
      # Skip code blocks and headers
      next line if line.match(/^```|^#|^-|\|/)

      # Check sentence length (approximate word count)
      words = line.split(/\s+/)
      if words.length > 15 && !line.strip.empty?
        # Split long sentences at commas or periods
        if line.include?(', ')
          parts = line.split(', ')
          if parts.length > 1
            modified = true
            parts.join(",\n")
          else
            line
          end
        else
          line
        end
      else
        line
      end
    end

    return unless modified

    File.write(filepath, formatted_lines.join("\n"))
    puts "  ✅ Applied formatting to #{filepath}"
  end

  def run_comprehensive_validation
    puts 'Running comprehensive validation...'

    run_rubocop_validation
    run_security_validation
    run_complexity_validation

    puts '✅ Comprehensive validation completed'
  end

  def run_rubocop_validation
    puts 'Running RuboCop validation...'

    output, status = Open3.capture2e("#{@gem_path}/rubocop --format json")

    @validation_results[:rubocop] = {
      exit_code: status.exitstatus,
      output: output,
      passed: status.success?
    }

    if status.success?
      puts '  ✅ RuboCop validation passed'
    else
      puts '  ❌ RuboCop validation failed'
      puts '  Running auto-correct...'

      # Run auto-correct
      auto_output, auto_status = Open3.capture2e("#{@gem_path}/rubocop --auto-correct")

      @validation_results[:rubocop_autocorrect] = {
        exit_code: auto_status.exitstatus,
        output: auto_output,
        passed: auto_status.success?
      }

      if auto_status.success?
        puts '  ✅ RuboCop auto-correct completed'
      else
        puts '  ⚠️  RuboCop auto-correct had issues'
      end
    end
  end

  def run_security_validation
    puts 'Running security validation...'

    # Run Brakeman if available
    if command_exists?('brakeman')
      output, status = Open3.capture2e("#{@gem_path}/brakeman --format json")

      @validation_results[:brakeman] = {
        exit_code: status.exitstatus,
        output: output,
        passed: status.success?
      }

      if status.success?
        puts '  ✅ Brakeman security scan passed'
      else
        puts '  ⚠️  Brakeman found potential security issues'
      end
    else
      puts '  ⚠️  Brakeman not available, skipping security validation'
    end
  end

  def run_complexity_validation
    puts 'Running complexity validation...'

    # Use RuboCop metrics for complexity validation
    output, status = Open3.capture2e("#{@gem_path}/rubocop --only Metrics")

    @validation_results[:complexity] = {
      exit_code: status.exitstatus,
      output: output,
      passed: status.success?
    }

    if status.success?
      puts '  ✅ Complexity validation passed'
    else
      puts '  ⚠️  Complexity issues found'
    end
  end

  def command_exists?(command)
    system("which #{command} > /dev/null 2>&1")
  end

  def generate_validation_report
    end_time = Time.now
    duration = end_time - @start_time

    # Calculate compliance score
    total_files = @processed_files.size
    failed_files = @failed_files.size
    passed_files = total_files - failed_files
    compliance_score = total_files > 0 ? (passed_files.to_f / total_files * 100).round(2) : 0

    report = {
      framework_version: @config['framework_version'],
      timestamp: end_time.strftime('%Y-%m-%dT%H:%M:%SZ'),
      duration_seconds: duration.round(2),
      compliance_score: compliance_score,
      total_files: total_files,
      passed_files: passed_files,
      failed_files: failed_files,
      threshold_met: compliance_score >= @config['extreme_scrutiny']['compliance_threshold'],
      processed_files: @processed_files,
      failures: @failed_files,
      validation_results: @validation_results
    }

    puts "\n" + ('=' * 80)
    puts "§ MASTER.JSON v#{@config['framework_version']} VALIDATION REPORT"
    puts '=' * 80
    puts "Timestamp: #{report[:timestamp]}"
    puts "Duration: #{duration.round(2)} seconds"
    puts "Compliance Score: #{compliance_score}%"
    puts "Threshold: #{@config['extreme_scrutiny']['compliance_threshold']}%"
    puts "Files Processed: #{total_files}"
    puts "Files Passed: #{passed_files}"
    puts "Files Failed: #{failed_files}"
    puts "Threshold Met: #{report[:threshold_met] ? '✅ YES' : '❌ NO'}"
    puts '=' * 80

    if failed_files > 0
      puts "\n❌ FAILURES:"
      @failed_files.each do |failure|
        puts "  - #{failure[:path]}: #{failure[:error]}"
      end
    end

    puts "\n📊 VALIDATION RESULTS:"
    @validation_results.each do |tool, result|
      status = result[:passed] ? '✅' : '❌'
      puts "  #{status} #{tool.upcase}: #{result[:passed] ? 'PASSED' : 'FAILED'}"
    end

    File.write('validation_report.json', JSON.pretty_generate(report))

    puts "\n✅ Validation report saved to validation_report.json"

    if report[:threshold_met]
      puts "\n🎉 COMPLIANCE ACHIEVED! Framework implementation successful."
    else
      puts "\n⚠️  COMPLIANCE THRESHOLD NOT MET. Additional work required."
    end
  end
end

# Run the validation suite
if __FILE__ == $0
  begin
    suite = MasterValidationSuite.new
    suite.execute_validation
  rescue StandardError => e
    puts "❌ Validation failed: #{e.message}"
    puts e.backtrace.first(5)
    exit 1
  end
end
