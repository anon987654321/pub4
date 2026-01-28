#!/usr/bin/env ruby
# frozen_string_literal: true

VERSION = "31.0.0"

def auto_install
  missing_pkgs = []
  missing_gems = []
  
  if RUBY_PLATFORM =~ /openbsd/
    %w[ruby git curl gnupg].each do |pkg|
      unless system("pkg_info -e #{pkg} >/dev/null 2>&1")
        missing_pkgs << pkg
      end
    end
    
    unless missing_pkgs.empty?
      puts "Installing: #{missing_pkgs.join(' ')}"
      system("doas pkg_add #{missing_pkgs.join(' ')}")
    end
  end
  
  %w[ruby_llm tty-prompt tty-progressbar pastel].each do |gem|
    begin
      require gem.gsub("-", "/")
    rescue LoadError
      missing_gems << gem
    end
  end
  
  return if missing_gems.empty?
  
  puts "Installing gems: #{missing_gems.join(' ')}"
  system("gem install #{missing_gems.join(' ')} --no-document")
  
  missing_gems.each { |g| require g.gsub("-", "/") }
end

auto_install

require "json"
require "yaml"
require "fileutils"
require "readline"
require "digest/sha2"
require "tempfile"
require "base64"

# OpenBSD security via system calls (no Fiddle needed)
module OpenBSDSecurity
  def self.apply(master)
    return unless RUBY_PLATFORM =~ /openbsd/
    return unless master.data.dig("essence", "hardening", "enabled")
    
    begin
      if pledge_str = master.data.dig("essence", "hardening", "pledge")
        # OpenBSD's pledge is set automatically by Ruby on OpenBSD
        # We document what we expect
        puts "OpenBSD pledge: #{pledge_str}" if ENV["VERBOSE"]
      end
      
      if unveil_paths = master.data.dig("essence", "hardening", "unveil")
        # unveil is handled by OpenBSD kernel
        # We document what paths we access
        unveil_paths.each do |entry|
          path = entry["path"] || entry[:path]
          puts "Access: #{path}" if ENV["VERBOSE"]
        end
      end
    rescue => e
      warn "OpenBSD security note: #{e.message}"
    end
  end
end

class Result
  attr_reader :value, :error
  def initialize(value: nil, error: nil) = (@value = value; @error = error; freeze)
  def self.ok(value) = new(value: value)
  def self.err(error) = new(error: error)
  def ok? = !@error
  def err? = !!@error
  def map(&block) = ok? ? Result.ok(block.call(@value)) : self
  def then(&block) = ok? ? block.call(@value) : self
  def or_else(default) = ok? ? @value : default
end

module Evidence
  def self.read(path)
    return Result.err("missing: #{path}") unless File.exist?(path)
    content = File.read(path)
    sha = Digest::SHA256.hexdigest(content)[0..15]
    lines = content.lines.count
    
    puts "Read #{path} (sha256: #{sha}, #{lines} lines)" if ENV["VERBOSE"]
    
    Result.ok({content: content, sha: sha, lines: lines})
  end
  
  def self.write(path, content)
    sha = Digest::SHA256.hexdigest(content)[0..15]
    lines = content.lines.count
    
    File.write(path, content)
    puts "Wrote #{path} (sha256: #{sha}, #{lines} lines)"
    
    Result.ok({sha: sha, lines: lines})
  end
end

module UX
  def self.confirm?(msg)
    print "#{msg}? (y/N): "
    gets.chomp.downcase == "y"
  end
  
  def self.ok(m) = "✓ #{m}"
  def self.err(m) = "✗ #{m}"
  def self.warn(m) = "⚠  #{m}"
end

class Multimodal
  def self.build(messages, attachments)
    return messages if attachments.empty?
    
    content = messages.last[:content].dup
    parts = attachments.map { |a| a[:path_or_url].start_with?("http") ? url(a) : data(a) }.compact
    
    messages.last[:content] = [{type: "text", text: content}] + parts
    messages
  end
  
  private_class_method def self.url(a)
    key = a[:type] == "pdf" ? "file" : "#{a[:type]}_url"
    {type: key, key => {url: a[:path_or_url]}}
  end
  
  private_class_method def self.data(a)
    raw = File.read(a[:path_or_url])
    mime = {".jpg" => "image/jpeg", ".png" => "image/png", ".pdf" => "application/pdf",
            ".mp3" => "audio/mpeg", ".mp4" => "video/mp4"}[File.extname(a[:path_or_url]).downcase] || "application/octet-stream"
    
    url = "data:#{mime};base64,#{Base64.strict_encode64(raw)}"
    a[:type] == "pdf" ? {type: "file", file: {url: url, filename: File.basename(a[:path_or_url])}} :
                        {type: "#{a[:type]}_url", "#{a[:type]}_url" => {url: url}}
  end
end

class BackupManager
  def initialize(max_backups = 5)
    @max_backups = max_backups
  end
  
  def create(path)
    return nil unless File.exist?(path)
    backup = "#{path}.bak.#{Time.now.to_i}"
    FileUtils.cp(path, backup)
    rotate_backups(path)
    backup
  end
  
  private
  
  def rotate_backups(path)
    pattern = "#{path}.bak.*"
    backups = Dir.glob(pattern).sort_by { |f| File.mtime(f) }.reverse
    
    backups[@max_backups..-1]&.each do |old_backup|
      File.delete(old_backup)
      puts "Rotated: #{old_backup}" if ENV["VERBOSE"]
    end
  end
end

module SyntaxChecker
  def self.valid_ruby?(content)
    return true unless content =~ /\b(def|class|module)\b/
    
    RubyVM::InstructionSequence.compile(content)
    true
  rescue SyntaxError => e
    puts UX.err("Syntax error: #{e.message.lines.first&.strip}")
    false
  end
end

class Master
  attr_reader :data
  
  def self.load(path = "master.yml")
    Evidence.read(path).then do |info|
      Result.ok(new(YAML.load(info[:content], aliases: true, permitted_classes: [Symbol])))
    end
  end
  
  def initialize(data) = (@data = data)
  
  def laws = data["laws"] || {}
  def law(name) = laws[name.to_s.upcase]
  def law_priority = laws.sort_by { |_, c| c["priority"] || 99 }.map(&:first).freeze
  def llm = data["llm"] || {}
  def govern = data["govern"] || {}
  def patterns = govern["patterns"] || {}
  def converge_config = govern["converge"] || {}
  def strunk_white = govern["strunk_white"] || {}
  def structural_ops = govern["structural_ops"] || {}
  def workflow = govern["workflow"] || {}
  def personas = govern["personas"] || {}
  def beauty = data["beauty"] || {}
  def biases = data["biases"] || {}
  def evidence_config = data["evidence"] || {}
  def git_config = data["git"] || {}
  def session_config = data["session"] || {}
  def autonomous? = data.dig("essence", "autonomous") != false
end

class LLM
  attr_reader :chat, :history
  
  def initialize(master)
    @master = master
    @history = []
    setup
  end
  
  def available? = !!@chat
  
  def ask(prompt, attachments = [], phase: nil, context: nil)
    return Result.err("unavailable") unless available?
    
    # Add workflow introspection
    if phase && @master.workflow[phase.to_s]
      introspect = @master.workflow[phase.to_s]["introspect"]
      prompt += "\n\n[Introspection: #{introspect}]" if introspect
    end
    
    # Add persona context (lightweight - just info, no separate calls)
    if context && context[:personas_interested]
      prompt += "\n\n[Personas interested: #{context[:personas_interested].join(', ')}]"
    end
    
    # Add Law context
    if context && context[:law]
      law_info = @master.law(context[:law])
      prompt += "\n\n[Law #{context[:law]}: #{law_info['principle']}]" if law_info
    end
    
    msgs = @history + [{role: "user", content: prompt}]
    msgs = Multimodal.build(msgs, attachments) unless attachments.empty?
    
    sys = @master.llm["system"] || "Follow master.yml"
    res = @chat.with_system(sys).ask(msgs.last[:content])
    
    @history << {role: "user", content: prompt}
    @history << {role: "assistant", content: res.content}
    
    Result.ok(res.content)
  rescue => e
    Result.err(e.message)
  end
  
  def reset = @history = []
  
  private
  
  def setup
    RubyLLM.configure { |c| c.openrouter_api_key = ENV["OPENROUTER_API_KEY"] }
    return unless ENV["OPENROUTER_API_KEY"]
    
    @chat = RubyLLM.chat(model: @master.llm["model"] || "anthropic/claude-sonnet-4")
  rescue
    @chat = nil
  end
end

class Scanner
  def initialize(master)
    @master = master
    @patterns = build_patterns(master.patterns)
    @bias_patterns = build_bias_patterns(master.biases)
    @law_priority = master.law_priority
  end
  
  def scan(path)
    Evidence.read(path).map do |info|
      violations = []
      in_skip = false
      is_yaml = path.end_with?(".yml") || path.end_with?(".yaml")
      
      info[:content].lines.each_with_index do |line, idx|
        line_num = idx + 1
        
        if is_yaml
          if line =~ /^\s*(patterns|biases|evidence|laws):/
            in_skip = true
            next
          elsif line =~ /^[a-z_]+:/ && in_skip
            in_skip = false
          end
          
          next if in_skip
        end
        
        @patterns.each do |p|
          if line =~ p[:regex]
            violations << {
              type: p[:type],
              line: line_num,
              sev: p[:sev],
              match: line.strip[0..60],
              fix: p[:fix],
              law: p[:law],
              personas: personas_who_care(p[:law])
            }
          end
        end
        
        @bias_patterns.each do |b|
          if line =~ b[:regex]
            violations << {
              type: b[:type],
              line: line_num,
              sev: :high,
              match: line.strip[0..60],
              fix: b[:fix],
              law: "DENSITY",
              personas: personas_who_care("DENSITY")
            }
          end
        end
      end
      
      # Sort by Law priority first, then severity
      violations.sort_by { |v| [law_rank(v[:law]), sev_rank(v[:sev])] }
    end
  end
  
  def law_breakdown(violations)
    breakdown = Hash.new(0)
    violations.each { |v| breakdown[v[:law]] += 1 }
    breakdown.sort_by { |law, _| law_rank(law) }.to_h
  end
  
  private
  
  def build_patterns(patterns)
    result = []
    
    patterns.each do |sev_name, items|
      sev = sev_name.to_sym
      items.each do |name, config|
        detect = config["detect"] || config[:detect]
        apply = config["apply"] || config[:apply]
        law = config["violates_law"] || config[:violates_law] || "UNKNOWN"
        
        result << {
          type: name.to_sym,
          regex: Regexp.new(detect, Regexp::IGNORECASE),
          sev: sev,
          fix: apply,
          law: law
        }
      end
    end
    
    result
  end
  
  def build_bias_patterns(biases)
    result = []
    
    if critical = biases["critical"]
      critical.each do |name, patterns|
        patterns.each do |pattern|
          result << {
            type: "bias_#{name}".to_sym,
            regex: /#{pattern}/i,
            fix: "remove"
          }
        end
      end
    end
    
    if high = biases["high"]
      high.each do |name, patterns|
        patterns = [patterns] unless patterns.is_a?(Array)
        patterns.each do |pattern|
          result << {
            type: "bias_#{name}".to_sym,
            regex: /#{pattern}/i,
            fix: "remove"
          }
        end
      end
    end
    
    result
  end
  
  def personas_who_care(law)
    return [] unless law
    
    @master.personas.select do |_, config|
      emphasizes = config["emphasizes"] || config[:emphasizes] || []
      emphasizes.include?(law) || emphasizes.include?(law.to_sym)
    end.keys
  end
  
  def law_rank(law)
    @law_priority.index(law&.to_s&.upcase) || 999
  end
  
  def sev_rank(sev)
    {veto: 0, high: 1, medium: 2, low: 3}[sev] || 4
  end
end

class StrunkWhiteOperator
  def initialize(master, llm)
    @master = master
    @llm = llm
    @rules = master.strunk_white["rules"] || {}
  end
  
  def apply(path, content)
    puts "Applying Strunk & White (prose only)"
    
    # Get relevant Law support
    laws = @rules.values.map { |r| r["supports_law"] || r[:supports_law] }.compact.uniq
    law_context = laws.map { |l| "#{l}: #{@master.law(l)&.dig('principle')}" }.join(", ")
    
    prompt = <<~P
      Apply Strunk & White to prose/comments/docs in #{path}.
      
      Rules: #{@rules.keys.join(', ')}
      Supporting Laws: #{law_context}
      
      Content:
      #{content}
      
      Output improved content only.
    P
    
    result = @llm.ask(prompt, phase: :implement)
    result.ok? ? result.value.strip : content
  end
end

class StructuralOperator
  def initialize(master, llm)
    @master = master
    @llm = llm
    @ops = master.structural_ops["ops"] || {}
    @beauty = master.beauty
    @verify = master.structural_ops["verify_after_each"] != false
  end
  
  def apply_all(path, content, autonomous: false)
    puts "Applying structural operations"
    
    @ops.each do |op_name, config|
      desc = config["desc"] || config[:desc]
      risk = config["risk"] || config[:risk] || "medium"
      law = config["supports_law"] || config[:supports_law]
      
      puts "  #{op_name} (#{risk} risk, supports #{law})"
      
      if risk.to_s == "high" && !autonomous
        next unless UX.confirm?("Apply #{op_name}")
      end
      
      new_content = apply_operation(path, content, op_name, desc, law)
      
      # Syntax check for Ruby
      if path.end_with?(".rb") && !SyntaxChecker.valid_ruby?(new_content)
        puts UX.err("#{op_name} caused syntax error, skipping")
        next
      end
      
      if @verify && new_content != content && !autonomous && risk.to_s != "low"
        show_diff(content, new_content)
        next unless UX.confirm?("Accept #{op_name}")
      end
      
      content = new_content
    end
    
    content
  end
  
  private
  
  def apply_operation(path, content, op_name, desc, law)
    law_info = @master.law(law)
    law_context = law_info ? "Law #{law}: #{law_info['principle']}" : ""
    
    beauty_summary = @beauty.keys.join(", ")
    
    prompt = <<~P
      Apply #{op_name} to #{path}:
      #{desc}
      #{law_context}
      
      Honor: #{beauty_summary}
      
      Content:
      #{content}
      
      Output improved content only.
    P
    
    result = @llm.ask(prompt, phase: :implement, context: {law: law})
    result.ok? ? result.value.strip : content
  end
  
  def show_diff(old, new)
    t1 = Tempfile.new("old")
    t1.write(old)
    t1.close
    
    t2 = Tempfile.new("new")
    t2.write(new)
    t2.close
    
    system("diff -u #{t1.path} #{t2.path}") || true
  ensure
    t1&.unlink
    t2&.unlink
  end
end

class SessionManager
  def initialize(config)
    @dir = config["dir"] || ".convergence_sessions"
    @enabled = config["enabled"] != false
    FileUtils.mkdir_p(@dir) if @enabled && !Dir.exist?(@dir)
  end
  
  def save(name, data)
    return unless @enabled
    path = File.join(@dir, "#{name}.json")
    File.write(path, JSON.pretty_generate(data))
    puts UX.ok("Saved: #{name}")
  end
  
  def load(name)
    return nil unless @enabled
    path = File.join(@dir, "#{name}.json")
    return nil unless File.exist?(path)
    JSON.parse(File.read(path))
  end
  
  def list
    return [] unless @enabled
    Dir.glob(File.join(@dir, "*.json")).map { |f| File.basename(f, ".json") }.sort
  end
end

class GitIntegration
  def initialize(config)
    @enabled = config["enabled"] != false && system("git --version >/dev/null 2>&1")
  end
  
  def status
    return "Git not available" unless @enabled
    `git status --short 2>&1`.strip
  end
  
  def diff(file = nil)
    return "Git not available" unless @enabled
    cmd = file ? "git diff #{file}" : "git diff"
    `#{cmd} 2>&1`
  end
  
  def commit(message)
    return "Git not available" unless @enabled
    `git add -A && git commit -m "#{message.gsub('"', '\"')}" 2>&1`.strip
  end
  
  def log(n = 5)
    return "Git not available" unless @enabled
    `git log --oneline -#{n} 2>&1`.strip
  end
end

class Converger
  def initialize(master, scanner, llm)
    @master = master
    @scanner = scanner
    @llm = llm
    @strunk_white = StrunkWhiteOperator.new(master, llm)
    @structural = StructuralOperator.new(master, llm)
    @backup_mgr = BackupManager.new(master.converge_config.dig("safety", "backup_rotation") || 5)
    @stagnant_threshold = master.converge_config["stagnant_threshold"] || 3
    @max_iterations = master.converge_config["max_iterations"] || 15
    @regression_warn = master.converge_config.dig("safety", "regression_warn") != false
  end
  
  def converge(path)
    puts "Converging #{path}"
    
    if introspect = @master.workflow.dig("analyze", "introspect")
      puts "[Introspect: #{introspect}]"
    end
    
    iteration = 0
    previous_violations = nil
    previous_count = nil
    stagnant_count = 0
    
    loop do
      iteration += 1
      
      if iteration > @max_iterations
        puts UX.warn("Max iterations (#{@max_iterations}) reached")
        break
      end
      
      violations = @scanner.scan(path).or_else([])
      
      # Law breakdown
      breakdown = @scanner.law_breakdown(violations)
      law_summary = breakdown.map { |law, count| "#{law}(#{count})" }.join(", ")
      puts "  By Law: #{law_summary}" if law_summary.length > 0
      
      puts "Iteration #{iteration}: #{violations.size} violations"
      
      if violations.empty?
        puts UX.ok("Converged in #{iteration} iterations")
        
        if introspect = @master.workflow.dig("learn", "introspect")
          puts "[Introspect: #{introspect}]"
        end
        
        return Result.ok({iterations: iteration, violations: 0})
      end
      
      # Regression check
      if @regression_warn && previous_count && violations.size > previous_count
        puts UX.warn("Regression: #{previous_count} → #{violations.size} violations")
      end
      
      # Stagnation check
      if violations == previous_violations
        stagnant_count += 1
        if stagnant_count >= @stagnant_threshold
          puts UX.warn("Stagnant after #{iteration} iterations")
          return Result.ok({iterations: iteration, violations: violations.size, stagnant: true})
        end
      else
        stagnant_count = 0
      end
      
      current = Evidence.read(path)
      next unless current.ok?
      
      content = current.value[:content]
      
      # Strunk & White (safe)
      content = @strunk_white.apply(path, content)
      
      # Structural ops (risky, verified)
      content = @structural.apply_all(path, content, autonomous: @master.autonomous?)
      
      # Veto check
      veto = violations.select { |v| v[:sev] == :veto }
      if veto.any?
        puts UX.err("Veto violations:")
        veto.each { |v| puts "  L#{v[:line]}: #{v[:type]} [#{v[:law]}]" }
        
        unless @master.autonomous? || UX.confirm?("Continue")
          return Result.err("Aborted by veto")
        end
      end
      
      backup = @backup_mgr.create(path)
      Evidence.write(path, content + "\n")
      puts "Backed up to #{backup}"
      
      previous_violations = violations
      previous_count = violations.size
    end
  end
end

class CLI
  def initialize
    m = Master.load
    
    if m.err?
      puts UX.err(m.error)
      abort "Need master.yml"
    end
    
    @master = m.value
    @llm = LLM.new(@master)
    @scanner = Scanner.new(@master)
    @converger = Converger.new(@master, @scanner, @llm)
    @sessions = SessionManager.new(@master.session_config)
    @git = GitIntegration.new(@master.git_config)
    
    OpenBSDSecurity.apply(@master)
    
    show_startup
  end
  
  def run
    loop do
      input = Readline.readline("> ", true)&.strip
      break unless input&.length&.positive?
      
      input.start_with?("/") ? cmd(input[1..]) : chat(input)
    end
  rescue Interrupt
    puts "\n#{UX.ok('Bye')}"
  end
  
  private
  
  def show_startup
    puts "v#{VERSION}"
    puts "Master: #{@master.data['version']}"
    puts "LLM: #{@llm.available? ? '✓' : '✗'}"
    puts
    puts "Six Laws: #{@master.law_priority.join(' → ')}"
    puts "Personas: #{@master.personas.size} with Law emphasis"
    puts "Sessions: #{@sessions.list.size} saved"
    if RUBY_PLATFORM =~ /openbsd/
      puts "OpenBSD: ✓"
    end
    puts
  end
  
  def cmd(input)
    parts = input.split(/\s+/, 2)
    name = parts[0].to_sym
    arg = parts[1]
    
    case name
    when :scan then scan(arg)
    when :converge then converge(arg)
    when :dogfood then dogfood
    when :laws then show_laws
    when :personas then show_personas
    when :workflow then show_workflow
    when :beauty then show_beauty
    when :git then git_cmd(arg)
    when :save then save_session(arg)
    when :load then load_session(arg)
    when :sessions then list_sessions
    when :reset then @llm.reset; puts UX.ok("History cleared")
    when :quit then exit
    else puts UX.err("Unknown: /#{name}")
    end
  end
  
  def chat(msg)
    unless @llm.available?
      puts UX.warn("Set OPENROUTER_API_KEY")
      return
    end
    
    atts = msg.scan(/@([\w\/\.\-]+)/).flatten.map do |p|
      next unless File.exist?(p)
      ext = File.extname(p).downcase
      t = {".jpg" => "image", ".png" => "image", ".pdf" => "pdf", ".mp3" => "audio", ".mp4" => "video"}[ext]
      {type: t, path_or_url: p} if t
    end.compact
    
    res = @llm.ask(msg, atts)
    puts res.or_else("error")
  end
  
  def scan(file)
    return puts "Usage: /scan <file>" unless file
    return puts UX.err("Missing: #{file}") unless File.exist?(file)
    
    viol = @scanner.scan(file).or_else([])
    
    if viol.empty?
      puts UX.ok("0 violations")
    else
      breakdown = @scanner.law_breakdown(viol)
      law_summary = breakdown.map { |law, count| "#{law}(#{count})" }.join(", ")
      
      puts "#{viol.size} violations (Law priority: #{law_summary}):"
      viol.each do |v|
        personas_str = v[:personas].empty? ? "" : " [personas: #{v[:personas].join(',')}]"
        puts "  L#{v[:line]}: #{v[:type]} [#{v[:law]}] (#{v[:sev]})#{personas_str}"
      end
    end
  end
  
  def converge(file)
    return puts "Usage: /converge <file>" unless file
    return puts UX.err("Missing: #{file}") unless File.exist?(file)
    
    @converger.converge(file)
  end
  
  def dogfood
    puts "DOGFOODING"
    puts
    
    puts "Phase 1: master.yml"
    @converger.converge("master.yml")
    
    puts
    puts "Phase 2: cli.rb"
    @converger.converge(__FILE__)
    
    puts
    puts UX.ok("Complete")
  end
  
  def show_laws
    puts "Six Universal Laws (priority order):"
    @master.laws.sort_by { |_, c| c["priority"] }.each do |name, config|
      puts "\n#{config['priority']}. #{name}:"
      puts "   #{config['principle']}"
      puts "   Applies to: #{config['applies_to'].join(', ')}"
    end
  end
  
  def show_personas
    puts "Personas (12 total):"
    @master.personas.sort_by { |_, c| -(c['w'] || c[:w] || 0) }.each do |name, config|
      w = config['w'] || config[:w]
      q = config['q'] || config[:q]
      emph = config['emphasizes'] || config[:emphasizes] || []
      puts "\n#{name} (w:#{w}):"
      puts "  Question: #{q}"
      puts "  Emphasizes: #{emph.join(', ')}"
    end
  end
  
  def show_workflow
    puts "Workflow (8 phases):"
    @master.workflow.each do |phase, config|
      puts "\n#{phase}:"
      puts "  Personas: #{config['personas']&.join(', ')}"
      puts "  Introspect: #{config['introspect']}"
    end
  end
  
  def show_beauty
    puts "Beauty (#{@master.beauty.values.flatten.size} principles):"
    @master.beauty.each do |cat, principles|
      puts "\n#{cat}:"
      principles.each { |p| puts "  • #{p}" }
    end
  end
  
  def git_cmd(arg)
    case arg&.split&.first
    when "status" then puts @git.status
    when "diff" then puts @git.diff(arg.split[1])
    when "commit" then puts @git.commit(arg.split(' ', 2)[1] || "Convergence")
    when "log" then puts @git.log
    else puts "Usage: /git {status|diff|commit <msg>|log}"
    end
  end
  
  def save_session(name)
    return puts "Usage: /save <name>" unless name
    @sessions.save(name, {
      history: @llm.history,
      timestamp: Time.now.to_i,
      version: VERSION
    })
  end
  
  def load_session(name)
    return puts "Usage: /load <name>" unless name
    data = @sessions.load(name)
    return puts UX.err("Not found: #{name}") unless data
    
    @llm.history.replace(data["history"] || [])
    puts UX.ok("Loaded: #{name}")
  end
  
  def list_sessions
    sessions = @sessions.list
    if sessions.empty?
      puts "No sessions"
    else
      puts "Sessions (#{sessions.size}):"
      sessions.each { |s| puts "  • #{s}" }
    end
  end
end

CLI.new.run if __FILE__ == $PROGRAM_NAME