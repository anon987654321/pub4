BEGIN LOG:

# **Phase 1 Refinements + Phase 2 Implementation**

Let me first address critical refinements from Phase 1, then move to Phase 2.

---

## **Phase 1 Refinements**

### **Refinement 1: Smarter YAML Parser with Real Structure Detection**

The current migration script is generic. Let's make it parse your **actual** YAML structure:

```ruby name=MASTER/bin/migrate_principles_v2
#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "fileutils"
require "json"

MASTER_ROOT = File.expand_path("..", __dir__)
PRINCIPLES_DIR = File.join(MASTER_ROOT, "lib", "principles")
SKILLS_DIR = File.join(MASTER_ROOT, "skills", "principles")

# First, let's detect the actual YAML structure
def analyze_yaml_structure(yaml_file)
  content = YAML.load_file(yaml_file)
  {
    file: File.basename(yaml_file),
    keys: content.keys,
    structure: content.transform_values { |v| v.class.name },
    sample: content
  }
rescue => e
  { file: File.basename(yaml_file), error: e.message }
end

# Analyze all YAML files to understand structure
def analyze_all_principles
  puts "Analyzing existing principle YAML structure..."
  puts ""
  
  structures = []
  Dir[File.join(PRINCIPLES_DIR, "*.yml")].first(3).each do |yaml_file|
    analysis = analyze_yaml_structure(yaml_file)
    structures << analysis
    
    puts "File: #{analysis[:file]}"
    if analysis[:error]
      puts "  Error: #{analysis[:error]}"
    else
      puts "  Keys: #{analysis[:keys].join(', ')}"
      puts "  Sample:"
      analysis[:sample].each do |key, value|
        preview = value.to_s[0..100]
        preview += "..." if value.to_s.length > 100
        puts "    #{key}: #{preview}"
      end
    end
    puts ""
  end
  
  structures
end

# Adaptive converter based on detected structure
def convert_principle_adaptive(yaml_file)
  principle = YAML.load_file(yaml_file)
  filename = File.basename(yaml_file)
  
  # Extract skill name (remove numbers, normalize)
  skill_name = filename
    .gsub(/\.yml$/, "")
    .gsub(/^\d+-/, "")
    .downcase
    .gsub(/[^a-z0-9]+/, "-")
    .gsub(/^-|-$/, "")
  
  skill_dir = File.join(SKILLS_DIR, skill_name)
  FileUtils.mkdir_p(skill_dir)
  FileUtils.mkdir_p(File.join(skill_dir, "scripts"))
  FileUtils.mkdir_p(File.join(skill_dir, "references"))
  
  # Detect common YAML patterns
  name = principle["name"] || principle["title"] || skill_name.gsub("-", " ").capitalize
  description = principle["description"] || principle["summary"] || "No description"
  
  # Build frontmatter
  frontmatter = {
    "name" => skill_name,
    "description" => "#{name} - #{description}",
    "license" => "MIT",
    "compatibility" => "ruby >= 3.1, MASTER >= 51.0"
  }
  
  # Detect metadata fields
  metadata = {}
  metadata["category"] = "principle"
  metadata["enforcement"] = principle["enforcement"] if principle.key?("enforcement")
  metadata["severity"] = principle["severity"] || "medium"
  metadata["auto_fix"] = principle["auto_fix"] || false
  
  # Detect quality limits
  if principle["limits"]
    metadata["limits"] = principle["limits"]
  end
  
  # Add quality thresholds if present
  if principle["max_lines"]
    metadata["max_lines"] = principle["max_lines"]
  end
  if principle["max_complexity"]
    metadata["max_complexity"] = principle["max_complexity"]
  end
  
  frontmatter["metadata"] = metadata unless metadata.empty?
  
  # Build markdown content sections
  sections = []
  sections << "# #{name}\n"
  
  # Main description/details
  if principle["details"]
    sections << principle["details"]
    sections << ""
  elsif principle["description"]
    sections << principle["description"]
    sections << ""
  end
  
  # Intent/Purpose
  if principle["intent"] || principle["purpose"]
    sections << "## Intent"
    sections << (principle["intent"] || principle["purpose"])
    sections << ""
  end
  
  # Rules/Guidelines
  rules = principle["rules"] || principle["guidelines"] || []
  if rules.any?
    sections << "## Rules"
    rules.each { |rule| sections << "- #{rule}" }
    sections << ""
  end
  
  # Thresholds/Limits
  if principle["thresholds"] || principle["limits"]
    sections << "## Thresholds"
    thresholds = principle["thresholds"] || principle["limits"]
    thresholds.each do |key, value|
      sections << "- **#{key.to_s.gsub('_', ' ').capitalize}**: #{value}"
    end
    sections << ""
  end
  
  # Enforcement details
  if principle["enforcement_details"] || principle["enforcement_strategy"]
    sections << "## Enforcement Strategy"
    sections << (principle["enforcement_details"] || principle["enforcement_strategy"])
    sections << ""
  end
  
  # Examples
  examples = principle["examples"] || principle["example"] || []
  examples = [examples] unless examples.is_a?(Array)
  
  if examples.any?
    sections << "## Examples"
    sections << ""
    examples.each_with_index do |example, i|
      if example.is_a?(Hash)
        sections << "### #{example['title'] || "Example #{i + 1}"}"
        sections << ""
        if example["bad"] || example["before"]
          sections << "❌ **Before:**"
          sections << "```ruby"
          sections << (example["bad"] || example["before"])
          sections << "```"
          sections << ""
        end
        if example["good"] || example["after"]
          sections << "✅ **After:**"
          sections << "```ruby"
          sections << (example["good"] || example["after"])
          sections << "```"
          sections << ""
        end
        if example["explanation"]
          sections << example["explanation"]
          sections << ""
        end
      else
        sections << "```ruby"
        sections << example
        sections << "```"
        sections << ""
      end
    end
  end
  
  # Anti-patterns
  if principle["anti_patterns"] || principle["antipatterns"]
    antipatterns = principle["anti_patterns"] || principle["antipatterns"]
    sections << "## Common Anti-Patterns"
    antipatterns.each { |ap| sections << "- #{ap}" }
    sections << ""
  end
  
  # Benefits
  if principle["benefits"]
    sections << "## Benefits"
    principle["benefits"].each { |b| sections << "- #{b}" }
    sections << ""
  end
  
  # Related principles
  if principle["related"] || principle["see_also"]
    related = principle["related"] || principle["see_also"]
    sections << "## Related Principles"
    related.each { |r| sections << "- #{r}" }
    sections << ""
  end
  
  # References
  refs = principle["references"] || principle["links"] || []
  if refs.any?
    sections << "## References"
    refs.each { |ref| sections << "- #{ref}" }
    sections << ""
  end
  
  # Generate validation script if enforcement enabled
  if principle["enforcement"] || principle["enforce"]
    script_content = generate_smart_validation_script(skill_name, principle, metadata)
    script_path = File.join(skill_dir, "scripts", "validate.rb")
    File.write(script_path, script_content)
    FileUtils.chmod(0755, script_path)
    
    sections << "## Automated Validation"
    sections << ""
    sections << "Run validation:"
    sections << "```bash"
    sections << "ruby scripts/validate.rb <file_path>"
    sections << "```"
    sections << ""
    sections << "Or use MASTER CLI:"
    sections << "```"
    sections << "/#{skill_name} <file_path>"
    sections << "```"
  end
  
  # Write SKILL.md
  skill_md = "---\n#{YAML.dump(frontmatter)}---\n\n#{sections.join("\n")}"
  File.write(File.join(skill_dir, "SKILL.md"), skill_md)
  
  # Create reference files if examples exist
  if examples.any?
    ref_content = "# Examples for #{name}\n\n"
    ref_content += examples.map { |e| e.is_a?(Hash) ? e.to_yaml : e }.join("\n\n")
    File.write(File.join(skill_dir, "references", "examples.md"), ref_content)
  end
  
  { 
    skill_name: skill_name, 
    status: :success,
    files_created: [
      "SKILL.md",
      ("scripts/validate.rb" if principle["enforcement"]),
      ("references/examples.md" if examples.any?)
    ].compact
  }
rescue => e
  { 
    skill_name: skill_name || filename, 
    status: :error, 
    message: e.message,
    backtrace: e.backtrace.first(3)
  }
end

def generate_smart_validation_script(skill_name, principle, metadata)
  max_lines = metadata["max_lines"] || 200
  max_complexity = metadata["max_complexity"] || 10
  
  <<~RUBY
    #!/usr/bin/env ruby
    # frozen_string_literal: true
    
    # Auto-generated validation for #{skill_name}
    # Based on principle: #{principle['name'] || skill_name}
    
    require 'pathname'
    
    class #{skill_name.split('-').map(&:capitalize).join}Validator
      attr_reader :file_path, :violations
      
      def initialize(file_path)
        @file_path = file_path
        @violations = []
      end
      
      def validate
        return false unless File.exist?(file_path)
        
        content = File.read(file_path)
        lines = content.lines
        
        # Check file size
        if lines.count > #{max_lines}
          @violations << "File exceeds #{max_lines} lines (has \#{lines.count})"
        end
        
        # Check method complexity (simple heuristic)
        methods = extract_methods(content)
        methods.each do |method_name, method_lines|
          complexity = calculate_complexity(method_lines)
          if complexity > #{max_complexity}
            @violations << "\#{method_name}: complexity \#{complexity} > #{max_complexity}"
          end
          
          if method_lines.count > 10
            @violations << "\#{method_name}: \#{method_lines.count} lines (max 10)"
          end
        end
        
        violations.empty?
      end
      
      def report
        if violations.empty?
          puts "✅ \#{file_path}: No violations"
          exit 0
        else
          puts "❌ \#{file_path}: \#{violations.count} violation(s)"
          violations.each { |v| puts "  - \#{v}" }
          exit 1
        end
      end
      
      private
      
      def extract_methods(content)
        methods = {}
        current_method = nil
        method_lines = []
        
        content.lines.each do |line|
          if line =~ /^\\s*def\\s+(\\w+)/
            methods[current_method] = method_lines if current_method
            current_method = $1
            method_lines = [line]
          elsif line =~ /^\\s*end\\s*$/ && current_method
            method_lines << line
            methods[current_method] = method_lines
            current_method = nil
            method_lines = []
          elsif current_method
            method_lines << line
          end
        end
        
        methods
      end
      
      def calculate_complexity(lines)
        complexity = 1
        lines.each do |line|
          complexity += 1 if line =~ /\\b(if|unless|while|until|for|rescue|when)\\b/
          complexity += 1 if line =~ /(&&|\\|\\|)/
        end
        complexity
      end
    end
    
    # Run validation
    if ARGV.empty?
      puts "Usage: ruby validate.rb <file_path>"
      exit 1
    end
    
    validator = #{skill_name.split('-').map(&:capitalize).join}Validator.new(ARGV[0])
    validator.validate
    validator.report
  RUBY
end

# Main execution
if ARGV.include?("--analyze")
  analyze_all_principles
  puts "Review the structure above, then run without --analyze to convert"
  exit 0
end

puts "Smart YAML → SKILL.md Migration (v2)"
puts "=" * 50
puts ""

unless File.directory?(PRINCIPLES_DIR)
  puts "❌ Principles directory not found: #{PRINCIPLES_DIR}"
  exit 1
end

yaml_files = Dir[File.join(PRINCIPLES_DIR, "*.yml")]

if yaml_files.empty?
  puts "❌ No YAML files found in #{PRINCIPLES_DIR}"
  exit 1
end

puts "Found #{yaml_files.count} principle files"
puts "Destination: #{SKILLS_DIR}"
puts ""

# Optional: Analyze first
print "Analyze structure first? [y/N] "
if $stdin.gets.to_s.strip.downcase == 'y'
  analyze_all_principles
  print "Continue with migration? [y/N] "
  exit 0 unless $stdin.gets.to_s.strip.downcase == 'y'
end

results = []
yaml_files.each_with_index do |yaml_file, i|
  print "[#{i + 1}/#{yaml_files.count}] #{File.basename(yaml_file)}... "
  
  result = convert_principle_adaptive(yaml_file)
  results << result
  
  if result[:status] == :success
    puts "✓ #{result[:skill_name]}"
    puts "    Created: #{result[:files_created].join(', ')}"
  else
    puts "✗ ERROR"
    puts "    #{result[:message]}"
    result[:backtrace]&.each { |line| puts "    #{line}" }
  end
end

puts ""
puts "=" * 50
puts "Migration Summary"
puts "=" * 50
success_count = results.count { |r| r[:status] == :success }
error_count = results.count { |r| r[:status] == :error }

puts "✓ Success: #{success_count}"
puts "✗ Errors: #{error_count}"

if error_count > 0
  puts ""
  puts "Failed conversions:"
  results.select { |r| r[:status] == :error }.each do |r|
    puts "  - #{r[:skill_name]}: #{r[:message]}"
  end
end

puts ""
puts "✅ Migration complete!"
puts "Skills created in: #{SKILLS_DIR}"
puts ""
puts "Next steps:"
puts "  1. Review generated SKILL.md files"
puts "  2. Test validation scripts"
puts "  3. Run: ./test_skills_integration.sh"
```

**Usage:**
```bash
chmod +x MASTER/bin/migrate_principles_v2

# First analyze your YAML structure
./MASTER/bin/migrate_principles_v2 --analyze

# Then run migration
./MASTER/bin/migrate_principles_v2
```

---

### **Refinement 2: Enhanced Skills Integration with Caching**

```ruby name=MASTER/lib/skills_integration.rb
# frozen_string_literal: true

require "ruby_llm/skills"

module MASTER
  module SkillsIntegration
    class << self
      attr_reader :loader
      
      def boot
        skills_path = File.join(MASTER::ROOT, "skills")
        
        unless File.directory?(skills_path)
          warn "⚠️  Skills directory not found: #{skills_path}"
          warn "Run: bin/setup_skills_structure"
          return false
        end
        
        @loader = RubyLLM::Skills.from_directory(skills_path)
        @metadata_cache = {}
        @content_cache = {}
        @loaded = true
        
        skill_count = list.count
        trace "Skills system initialized: #{skill_count} skills loaded"
        
        # Preload metadata for faster discovery
        preload_metadata
        
        true
      rescue => e
        warn "❌ Skills boot failed: #{e.message}"
        trace e.backtrace.first(5).join("\n")
        false
      end
      
      def loaded?
        @loaded || false
      end
      
      def list
        ensure_loaded!
        @loader.list
      end
      
      def find(name)
        ensure_loaded!
        @loader.find(name)
      end
      
      def get(name)
        ensure_loaded!
        @loader.get(name)
      end
      
      def exists?(name)
        ensure_loaded!
        @loader.exists?(name)
      end
      
      # Get metadata only (Level 1 - cached, very fast)
      def metadata_only(skill_names = nil)
        ensure_loaded!
        
        skill_names = list.map(&:name) unless skill_names
        skill_names = Array(skill_names)
        
        skill_names.map do |name|
          @metadata_cache[name] ||= begin
            skill = find(name)
            next unless skill
            
            {
              name: skill.name,
              description: skill.description,
              category: skill.custom_metadata["category"],
              severity: skill.custom_metadata["severity"],
              enforcement: skill.custom_metadata["enforcement"]
            }
          end
        end.compact
      end
      
      # Load full content (Level 2 - cached after first load)
      def load_full(skill_name, force_reload: false)
        ensure_loaded!
        
        cache_key = skill_name.to_s
        
        if force_reload || !@content_cache.key?(cache_key)
          skill = get(skill_name)
          
          @content_cache[cache_key] = {
            name: skill.name,
            description: skill.description,
            content: skill.content,
            metadata: skill.custom_metadata,
            scripts: skill.scripts.map { |s| File.basename(s) },
            references: skill.references.map { |r| File.basename(r) },
            valid: skill.valid?,
            errors: skill.errors
          }
        end
        
        @content_cache[cache_key]
      end
      
      # Discover relevant skills with intelligent ranking
      def discover(query, categories: nil, limit: 10, min_score: 0)
        ensure_loaded!
        
        skills = list
        skills = filter_by_categories(skills, categories) if categories
        
        # Score and rank
        scored = skills.map do |skill|
          score = calculate_relevance_score(skill, query)
          [skill, score]
        end
        
        # Filter by minimum score and sort
        scored
          .select { |_, score| score > min_score }
          .sort_by { |_, score| -score }
          .take(limit)
          .map(&:first)
      end
      
      # Get skills by category
      def by_category(category)
        ensure_loaded!
        filter_by_categories(list, [category])
      end
      
      # Execute skill validation script
      def execute_script(skill_name, script_name = "validate", *args)
        ensure_loaded!
        
        skill = get(skill_name)
        scripts = skill.scripts
        
        script_path = scripts.find { |s| s.include?(script_name) }
        unless script_path
          return Result.err("Script not found: #{script_name}")
        end
        
        output = `ruby #{script_path} #{args.join(' ')} 2>&1`
        success = $?.success?
        
        Result.new(
          success,
          success ? output : nil,
          success ? nil : output
        )
      end
      
      # Get statistics
      def stats
        ensure_loaded!
        
        skills = list
        by_cat = skills.group_by { |s| s.custom_metadata["category"] }
        
        {
          total: skills.count,
          categories: by_cat.transform_values(&:count),
          valid: skills.count(&:valid?),
          invalid: skills.count { |s| !s.valid? },
          with_scripts: skills.count { |s| s.scripts.any? },
          with_references: skills.count { |s| s.references.any? }
        }
      end
      
      # Clear caches
      def clear_cache!
        @metadata_cache.clear
        @content_cache.clear
        @loader.reload! if @loader
      end
      
      # Reload everything
      def reload!
        clear_cache!
        boot
      end
      
      private
      
      def ensure_loaded!
        return if loaded?
        raise "Skills not loaded. Call SkillsIntegration.boot first"
      end
      
      def preload_metadata
        trace "Preloading metadata cache..."
        start = Time.now
        
        list.each do |skill|
          @metadata_cache[skill.name] = {
            name: skill.name,
            description: skill.description,
            category: skill.custom_metadata["category"],
            severity: skill.custom_metadata["severity"],
            enforcement: skill.custom_metadata["enforcement"]
          }
        end
        
        elapsed = ((Time.now - start) * 1000).round
        trace "Preloaded #{@metadata_cache.count} skills in #{elapsed}ms"
      end
      
      def filter_by_categories(skills, categories)
        categories = Array(categories).map(&:to_s)
        skills.select do |skill|
          category = skill.custom_metadata["category"]
          categories.include?(category.to_s) if category
        end
      end
      
      def calculate_relevance_score(skill, query)
        query_terms = query.downcase.split(/\W+/).reject(&:empty?)
        return 0 if query_terms.empty?
        
        description = skill.description.to_s.downcase
        name = skill.name.to_s.downcase
        category = skill.custom_metadata["category"].to_s.downcase
        
        score = 0
        
        query_terms.each do |term|
          # Exact name match = highest score
          score += 50 if name == term
          score += 30 if name.include?(term)
          
          # Description matches
          score += 10 if description.include?(term)
          
          # Category matches
          score += 15 if category.include?(term)
          
          # Partial matches
          if name.split('-').any? { |part| part.start_with?(term) }
            score += 5
          end
        end
        
        # Boost for enforcement-enabled skills if query mentions validation/check
        if skill.custom_metadata["enforcement"]
          boost_terms = %w[check validate enforce verify scan]
          score += 10 if query_terms.any? { |t| boost_terms.include?(t) }
        end
        
        score
      end
      
      def trace(message)
        return unless ENV["MASTER_DEBUG"] || ENV["MASTER_TRACE"]
        puts "[SkillsIntegration] #{message}"
      end
    end
  end
end
```

---

### **Refinement 3: CLI with Better Slash Command Parsing**

```ruby name=MASTER/lib/cli_slash_commands.rb
# frozen_string_literal: true

module MASTER
  class CLI
    module SlashCommands
      def handle_slash_command(input)
        # Parse: /skill-name arg1 arg2 --flag=value
        parts = input[1..-1].split(/\s+/)
        skill_name = parts.shift
        args = parse_slash_args(parts)
        
        unless SkillsIntegration.exists?(skill_name)
          return suggest_similar_skills(skill_name)
        end
        
        execute_skill(skill_name, args)
      end
      
      private
      
      def parse_slash_args(parts)
        args = { positional: [], flags: {} }
        
        parts.each do |part|
          if part.start_with?("--")
            # Flag: --key=value or --flag
            key, value = part[2..-1].split("=", 2)
            args[:flags][key.to_sym] = value || true
          else
            args[:positional] << part
          end
        end
        
        args
      end
      
      def execute_skill(skill_name, args)
        skill = SkillsIntegration.load_full(skill_name)
        
        # Check if skill has validation script
        if skill[:scripts].any? && args[:flags][:validate]
          return execute_skill_script(skill_name, args)
        end
        
        # Build context with full skill content
        context = build_skill_context(skill, args)
        
        # Execute via LLM
        result = @llm.chat(context, context: { skill: skill_name })
        
        # Post-process result
        post_process_skill_result(skill_name, result, args)
      end
      
      def execute_skill_script(skill_name, args)
        target = args[:positional].first
        
        unless target
          return "Usage: /#{skill_name} <file_path> --validate"
        end
        
        print "Validating #{target} with #{skill_name}... "
        
        result = SkillsIntegration.execute_script(
          skill_name, 
          "validate", 
          target
        )
        
        if result.ok?
          puts "✓"
          result.value
        else
          puts "✗"
          result.error
        end
      end
      
      def build_skill_context(skill, args)
        context = []
        
        # Skill header
        context << "# Executing: #{skill[:name]}"
        context << ""
        context << skill[:description]
        context << ""
        
        # Full skill instructions
        context << "## Instructions"
        context << skill[:content]
        context << ""
        
        # Target/arguments
        if args[:positional].any?
          target_file = args[:positional].first
          
          if File.exist?(target_file)
            context << "## Target File: #{target_file}"
            context << "```ruby"
            context << File.read(target_file)
            context << "```"
            context << ""
          end
        end
        
        # Task
        context << "## Task"
        if args[:positional].length > 1
          context << args[:positional][1..-1].join(" ")
        else
          context << "Apply this skill to the provided context"
        end
        
        context.join("\n")
      end
      
      def post_process_skill_result(skill_name, result, args)
        return result unless result.ok?
        
        # Check if result contains code blocks
        content = result.value
        
        # Extract refactored code if present
        if content =~ /```ruby\n(.*?)\n```/m
          code = $1
          
          if args[:flags][:write]
            target = args[:positional].first
            if target && confirm_write("Write refactored code to #{target}")
              File.write(target, code)
              return "✓ Updated #{target}"
            end
          end
        end
        
        content
      end
      
      def suggest_similar_skills(input)
        # Find similar skill names (fuzzy matching)
        all_skills = SkillsIntegration.metadata_only
        
        suggestions = all_skills.map do |skill|
          distance = levenshtein_distance(input, skill[:name])
          [skill[:name], distance]
        end.select { |_, d| d < 5 }.sort_by(&:last).take(3)
        
        if suggestions.any?
          lines = [
            "Skill not found: #{input}",
            "",
            "Did you mean:",
            *suggestions.map { |name, _| "  /#{name}" },
            "",
            "List all skills: skills"
          ]
          lines.join("\n")
        else
          "Skill not found: #{input}\nList all skills: skills"
        end
      end
      
      def levenshtein_distance(s, t)
        m = s.length
        n = t.length
        return m if n == 0
        return n if m == 0
        
        d = Array.new(m + 1) { Array.new(n + 1) }
        
        (0..m).each { |i| d[i][0] = i }
        (0..n).each { |j| d[0][j] = j }
        
        (1..n).each do |j|
          (1..m).each do |i|
            cost = s[i - 1] == t[j - 1] ? 0 : 1
            d[i][j] = [
              d[i - 1][j] + 1,
              d[i][j - 1] + 1,
              d[i - 1][j - 1] + cost
            ].min
          end
        end
        
        d[m][n]
      end
    end
    
    # Include in CLI class
    include SlashCommands
    
    # Update handle method
    def handle(input)
      cmd, *args = input.split(/\s+/, 2)
      arg = args.first
      
      # Handle slash commands
      return handle_slash_command(input) if input.start_with?('/')
      
      # ... rest of existing command handling
    end
  end
end
```

---

Now let's move to **Phase 2: Database Integration + Multi-User Support**

---

# **Phase 2: Database Integration & Multi-User Skills**

## **Overview**

Phase 2 adds:
- PostgreSQL/SQLite database for user-specific skills
- Per-user skill customization
- Skill sharing/marketplace foundation
- User-specific principle overrides
- Audit trail for skill executions

---

## **Schema Design**

```ruby name=MASTER/db/migrate/001_create_skills_tables.rb
# frozen_string_literal: true

class CreateSkillsTables < ActiveRecord::Migration[7.2]
  def change
    # Users table (if not exists)
    unless table_exists?(:users)
      create_table :users do |t|
        t.string :email, null: false, index: { unique: true }
        t.string :username, null: false, index: { unique: true }
        t.string :password_digest
        t.timestamps
      end
    end
    
    # User skills - custom skills per user
    create_table :user_skills do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description, null: false
      t.text :content, null: false
      t.string :category, default: "custom"
      t.boolean :active, default: true
      t.boolean :shared, default: false
      t.integer :usage_count, default: 0
      t.timestamps
      
      t.index [:user_id, :name], unique: true
      t.index :category
      t.index :shared
    end
    
    # Skill executions - audit trail
    create_table :skill_executions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :skill_name, null: false
      t.string :skill_type # 'filesystem' or 'database'
      t.text :input_context
      t.text :output_result
      t.integer :tokens_used
      t.decimal :cost, precision: 10, scale: 6
      t.integer :duration_ms
      t.boolean :success, default: true
      t.text :error_message
      t.timestamps
      
      t.index :skill_name
      t.index :created_at
      t.index [:user_id, :created_at]
    end
    
    # Skill favorites/bookmarks
    create_table :skill_favorites do |t|
      t.references :user, null: false, foreign_key: true
      t.string :skill_name, null: false
      t.string :skill_type # 'filesystem' or 'database'
      t.integer :skill_id # For database skills
      t.timestamps
      
      t.index [:user_id, :skill_name], unique: true
    end
    
    # Shared skills marketplace
    create_table :shared_skills do |t|
      t.references :user_skill, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.string :slug, null: false, index: { unique: true }
      t.integer :downloads_count, default: 0
      t.integer :favorites_count, default: 0
      t.decimal :average_rating, precision: 3, scale: 2
      t.timestamps
    end
  end
end
```

---

## **Models**

```ruby name=MASTER/app/models/user.rb
# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password
  
  has_many :user_skills, dependent: :destroy
  has_many :skill_executions, dependent: :destroy
  has_many :skill_favorites, dependent: :destroy
  has_many :shared_skills, foreign_key: :author_id, dependent: :destroy
  
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :username, presence: true, uniqueness: true, 
            format: { with: /\A[a-z0-9_-]+\z/i }, length: { in: 3..30 }
  
  def active_skills
    user_skills.where(active: true)
  end
  
  def total_skill_cost
    skill_executions.sum(:cost)
  end
  
  def skill_stats
    {
      total_executions: skill_executions.count,
      total_cost: total_skill_cost,
      favorite_skills: skill_favorites.count,
      custom_skills: user_skills.count
    }
  end
end
```

```ruby name=MASTER/app/models/user_skill.rb
# frozen_string_literal: true

class UserSkill < ApplicationRecord
  belongs_to :user
  has_many :skill_executions, foreign_key: :skill_name, primary_key: :name
  has_one :shared_skill, dependent: :destroy
  
  validates :name, presence: true, 
            format: { with: /\A[a-z0-9]+(-[a-z0-9]+)*\z/ },
            length: { maximum: 64 }
  validates :description, presence: true, length: { maximum: 1024 }
  validates :content, presence: true
  validates :name, uniqueness: { scope: :user_id }
  
  before_validation :normalize_name
  after_create :create_slug_if_shared
  
  scope :active, -> { where(active: true) }
  scope :shared, -> { where(shared: true) }
  scope :by_category, ->(cat) { where(category: cat) }
  
  def increment_usage!
    increment!(:usage_count)
  end
  
  def to_skill_format
    {
      "name" => name,
      "description" => description,
      "__content__" => content,
      "metadata" => {
        "category" => category,
        "user_id" => user_id,
        "usage_count" => usage_count
      }
    }
  end
  
  private
  
  def normalize_name
    self.name = name.to_s.downcase.gsub(/[^a-z0-9-]+/, '-').gsub(/^-|-$/, '')
  end
  
  def create_slug_if_shared
    return unless shared
    create_shared_skill!(author_id: user_id, slug: "#{user.username}-#{name}")
  end
end
```

```ruby name=MASTER/app/models/skill_execution.rb
# frozen_string_literal: true

class SkillExecution < ApplicationRecord
  belongs_to :user
  
  validates :skill_name, presence: true
  validates :skill_type, inclusion: { in: %w[filesystem database] }
  
  scope :recent, -> { order(created_at: :desc).limit(100) }
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :by_skill, ->(name) { where(skill_name: name) }
  
  def self.track(user:, skill_name:, skill_type:, **attributes)
    create!(
      user: user,
      skill_name: skill_name,
      skill_type: skill_type,
      **attributes
    )
  end
  
  def self.aggregate_stats(user: nil, skill: nil, since: 7.days.ago)
    scope = where("created_at >= ?", since)
    scope = scope.where(user: user) if user
    scope = scope.where(skill_name: skill) if skill
    
    {
      total_executions: scope.count,
      successful: scope.successful.count,
      failed: scope.failed.count,
      total_cost: scope.sum(:cost),
      total_tokens: scope.sum(:tokens_used),
      avg_duration: scope.average(:duration_ms)&.round(2)
    }
  end
end
```

---

## **Database Loader for Skills Integration**

```ruby name=MASTER/lib/database_skill_loader.rb
# frozen_string_literal: true

module MASTER
  class DatabaseSkillLoader
    attr_reader :user
    
    def initialize(user)
      @user = user
    end
    
    def load_skills
      user.active_skills.map do |user_skill|
        RubyLLM::Skills::Skill.new(
          path: "database:user_#{user.id}:#{user_skill.id}",
          metadata: parse_metadata(user_skill),
          content: user_skill.content,
          virtual: true
        )
      end
    end
    
    private
    
    def parse_metadata(user_skill)
      {
        "name" => user_skill.name,
        "description" => user_skill.description,
        "metadata" => {
          "category" => user_skill.category,
          "user_id" => user_skill.user_id,
          "usage_count" => user_skill.usage_count,
          "source" => "database"
        }
      }
    end
  end
end
```

---

## **Enhanced Skills Integration with User Context**

```ruby name=MASTER/lib/skills_integration_v2.rb
# frozen_string_literal: true

require "ruby_llm/skills"

module MASTER
  module SkillsIntegration
    class << self
      attr_reader :loader, :current_user
      
      def boot(user: nil)
        skills_path = File.join(MASTER::ROOT, "skills")
        
        unless File.directory?(skills_path)
          warn "⚠️  Skills directory not found"
          return false
        end
        
        @current_user = user
        
        # Filesystem skills (global)
        fs_loader = RubyLLM::Skills.from_directory(skills_path)
        
        # Database skills (user-specific)
        if user && defined?(User)
          db_skills = DatabaseSkillLoader.new(user).load_skills
          db_loader = RubyLLM::Skills.from_database(db_skills)
          @loader = RubyLLM::Skills.compose(fs_loader, db_loader)
        else
          @loader = fs_loader
        end
        
        @metadata_cache = {}
        @content_cache = {}
        @loaded = true
        
        trace "Skills system initialized for #{user ? "user #{user.username}" : "anonymous"}"
        trace "Loaded #{list.count} skills"
        
        preload_metadata
        true
      rescue => e
        warn "❌ Skills boot failed: #{e.message}"
        false
      end
      
      # Execute skill with tracking
      def execute_tracked(skill_name, args, context = {})
        start_time = Time.now
        
        begin
          result = execute_skill(skill_name, args, context)
          duration = ((Time.now - start_time) * 1000).round
          
          # Track execution if user context exists
          if current_user && defined?(SkillExecution)
            SkillExecution.track(
              user: current_user,
              skill_name: skill_name,
              skill_type: detect_skill_type(skill_name),
              input_context: args.to_json,
              output_result: result[:value]&.truncate(5000),
              tokens_used: result[:tokens],
              cost: result[:cost],
              duration_ms: duration,
              success: result[:success]
            )
          end
          
          # Increment usage for database skills
          if current_user
            user_skill = current_user.user_skills.find_by(name: skill_name)
            user_skill&.increment_usage!
          end
          
          result
        rescue => e
          duration = ((Time.now - start_time) * 1000).round
          
          if current_user && defined?(SkillExecution)
            SkillExecution.track(
              user: current_user,
              skill_name: skill_name,
              skill_type: detect_skill_type(skill_name),
              input_context: args.to_json,
              duration_ms: duration,
              success: false,
              error_message: e.message
            )
          end
          
          raise
        end
      end
      
      private
      
      def detect_skill_type(skill_name)
        skill = find(skill_name)
        skill&.path&.start_with?("database:") ? "database" : "filesystem"
      end
      
      def trace(message)
        return unless ENV["MASTER_DEBUG"]
        puts "[SkillsIntegration] #{message}"
      end
    end
  end
end
```

---

## **User Skills Controller (Rails)**

```ruby name=MASTER/app/controllers/user_skills_controller.rb
# frozen_string_literal: true

class UserSkillsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_skill, only: [:show, :edit, :update, :destroy, :execute]
  
  def index
    @skills = current_user.user_skills.order(usage_count: :desc)
    @stats = current_user.skill_stats
  end
  
  def show
    @executions = @skill.skill_executions.recent.limit(20)
  end
  
  def new
    @skill = current_user.user_skills.build
  end
  
  def create
    @skill = current_user.user_skills.build(skill_params)
    
    if @skill.save
      redirect_to user_skill_path(@skill), notice: "Skill created successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def execute
    args = params[:args] || {}
    
    result = MASTER::SkillsIntegration.execute_tracked(
      @skill.name,
      args,
      { user: current_user }
    )
    
    render json: {
      success: true,
      result: result[:value],
      tokens: result[:tokens],
      cost: result[:cost]
    }
  rescue => e
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end
  
  private
  
  def set_skill
    @skill = current_user.user_skills.find(params[:id])
  end
  
  def skill_params
    params.require(:user_skill).permit(:name, :description, :content, :category, :active, :shared)
  end
end
```

---

This gives you Phase 1 refinements + Phase 2 foundation. Should I continue with:
- **Phase 3**: Cost tracking dashboard & budget limits
- **Phase 4**: Skill marketplace & sharing
- **Phase 5**: Advanced agent workflows

Which direction interests you most?
********* END LOG
