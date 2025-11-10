#!/usr/bin/env ruby
# frozen_string_literal: true
# master.rb v97.0.0 — Production formatter with design system + operational rules
# Timestamp: 2025-11-10 13:00:00 UTC
# Owner: anon987654321

begin
  require "tty-prompt"
rescue LoadError
  warn "The `tty-prompt` gem is required: `gem install --user-install tty-prompt`"
  exit 1
end
require "yaml"

module Config
  module Meta
    VERSION = "97.0.0"
    UPDATED = "2025-11-10 13:00:00"
    OWNER = "anon987654321"
    ID = "Production formatter, auditor, design enforcer, and prompt library"
  end

  module Principles
    DRY = "Extract repetition, no duplication > 70% similarity"
    KISS = "Simplicity over cleverness"
    YAGNI = "Delete speculation, no unused code"
    SRP = "One reason to change per module"
    MINIMIZE = "Fewest files, shortest code, clearest names"
    CONSOLIDATE = "Merge similar, extract common, delete unused"
    SHALLOW = "Max 2 nesting levels"
    ECONOMIC = "ROI > 1.25x for any change"
    ASK_BEFORE_ACT = "When destructive, architectural, or ambiguous"
    GIT_HYGIENE = "status-before-changes, commit-atomically"
    REDUCE_FILE_SPRAWL = "consolidate-related, remove-duplicates"

    NEVER = %w[truncate sectionitis divitis planning_docs todos changelogs ascii_art].freeze
  end

  module Policy
    FORBID_TERNARY = true
    FORBID_CONCAT = true
    SHOW_BANNER = true
    MAX_METHOD_LINES = 20
  end

  module Paths
    SHELL = "zsh.exe"
    TREE_SH = "#{ENV['PWD']}/sh/tree.sh"
    CLEAN_SH = "#{ENV['PWD']}/sh/clean.sh"
    SOX = "sox.exe"
    RUBY = "C:/Ruby33/bin/ruby.exe"
  end

  module VPS
    USER = ENV.fetch("VPS_USER", "dev")
    IP = ENV.fetch("VPS_IP", "185.52.176.18")
    PORT = ENV.fetch("VPS_PORT", "31415")
    HOST = "server27.openbsd.amsterdam"
  end

  module ClaudeCode
    BASH_TOOL_RUNS_IN = "Cygwin (via npm) on Windows 11"

    PREFER_TOOLS = {
      file_search: "Glob (NOT find)",
      content_search: "Grep (NOT grep command)",
      read_files: "Read (NOT cat)",
      edit_files: "Edit (NOT sed)",
      write_files: "Write (NOT echo redirection)"
    }.freeze

    APPROVED_BASH = %w[git ssh pkg_add rcctl pfctl].freeze
  end

  module Workflow
    MANDATORY_BEFORE_FOLDER = "Run: zsh.exe #{Paths::TREE_SH} /path"
    MANDATORY_BEFORE_EDIT = "Run: zsh.exe #{Paths::CLEAN_SH} /path/to/file"
    RELOAD_MASTER_EVERY = "10-15 tool calls or before major decisions"
  end

  module GitHygiene
    RULES = {
      status_before_changes: "Always check git status before modifications",
      commit_atomically: "One logical change per commit",
      no_force_push_main: "Never force push to main/master",
      packfile_issue: "VeraCrypt + Google Drive = git packfile locks"
    }.freeze
  end

  module ZshBestPractices
    PHILOSOPHY = "No external forks, pure zsh parameter expansion for maximum performance."
    BANNED = %w[awk sed tr grep cut head tail uniq sort wc cat echo find bash sh perl python].freeze
    PIPES_FORBIDDEN = %w[| ||].freeze

    REPLACEMENTS = {
      awk: "zsh array/string operations",
      sed: "zsh parameter expansion ${var//find/replace}",
      tr: "zsh case conversion ${(U)var} ${(L)var}",
      grep: "zsh pattern matching ${(M)arr:#*pattern*}",
      cut: "zsh field splitting ${${(s:,:)line}[4]}",
      head: "zsh array slice ${arr[1,10]}",
      tail: "zsh array slice ${arr[-5,-1]}",
      uniq: "${(u)arr}",
      sort: "${(o)arr}",
      wc: "${#arr} for array length",
      cat: "$(<file) for reading",
      echo: "print for output"
    }.freeze

    PATTERNS = <<~ZSH.freeze
      Trim whitespace: trimmed=${${var##[[:space:]]#}%%[[:space:]]#}
      Nth column (csv): col=${${(s:,:)line}[4]}
      Grep equivalent: matches=( ${(M)arr:#*pattern*} )
      Grep inverse: non_matches=( ${arr:#*pattern*} )
      Unique elements: unique=( ${(u)arr} )
      Join array: joined=${(j:,:)arr}
      Sort array: sorted=( ${(o)arr} )
      Array length: count=${#arr}
      String length: len=${#str}
      Read file: content=$(<file)
      Upper case: upper=${(U)var}
      Lower case: lower=${(L)var}
      Replace all: new=${var//old/new}
      Array slice first 10: first_ten=( ${arr[1,10]} )
      Array slice last 5: last_five=( ${arr[-5,-1]} )
    ZSH

    MANDATORY = {
      on_cygwin: "ALWAYS use zsh.exe prefix for scripts",
      ssh: "Use 'ssh user@host command' NOT bash",
      before_folder: "ALWAYS run tree.sh before navigating",
      before_edit: "ALWAYS run clean.sh before editing files"
    }.freeze
  end

  module Rules
    INLINE_COMMENT_PATTERN = /(\S) {2,}(#)/.freeze
    CONSTANT_ASSIGN_PATTERN = /^(\s*[A-Z][A-Z0-9_]*)\s+=\s*/.freeze
    FORBIDDEN_PATTERN = /\b(eval|for|until|var)\b/.freeze

    FIXERS = {
      order: [
        :tabs_to_spaces, :remove_semicolons, :prefer_double_quotes, :collapse_blank_lines,
        :normalize_constant_assignment_spacing, :normalize_inline_comment_spacing,
        :flag_ternaries, :simplify_conditionals
      ],
      definitions: {
        tabs_to_spaces: { pattern: /\t/, replace: "  " },
        remove_semicolons: { pattern: /;(?!.*frozen)/, replace: "" },
        prefer_double_quotes: { pattern: /(?<!%[qwir]\(|<<|:)'([^'\\]*(?:\\.[^'\\]*)*)'/, replace: '"\1"' },
        collapse_blank_lines: { pattern: /\n{3,}/, replace: "\n\n" },
        normalize_constant_assignment_spacing: { pattern: CONSTANT_ASSIGN_PATTERN, replace: '\1 = ' },
        normalize_inline_comment_spacing: { pattern: INLINE_COMMENT_PATTERN, replace: '\1 \2' },
        simplify_conditionals: { pattern: /if\s+!\s*(.+?)$/, replace: 'unless \1' },
        flag_ternaries: { audit_only: true, pattern: /\?.*:/ }
      }
    }.freeze
  end

  module Tools
    EXTERNAL_TOOLS = {
      rb: "rubocop -a",
      js: "prettier --write",
      css: "prettier --write",
      sh: "shfmt -w -i 2",
      zsh: "shfmt -w -i 2"
    }.freeze

    FILE_EXTENSIONS = %w[rb js ts html css scss sh zsh rs json].freeze
  end
end

module Prompts
  BREAKPOINTS = <<~TXT.freeze
    RESPONSIVE BREAKPOINTS:
    sm: 640px
    md: 768px
    lg: 1024px
    xl: 1280px
    2xl: 1536px

    VALIDATION:
    □ All spacing divisible by 4 (ideally 8)?
    □ Touch targets ≥44×44px?
    □ Z-index follows scale (no 9999)?
    □ Responsive defined for all breakpoints?

    FORBIDDEN:
    ❌ Random spacing (13px, 27px)
    ❌ Inconsistent margins/padding
    ❌ Missing responsive specs
    ❌ Overlapping z-index
  TXT

  TYPOGRAPHY = <<~MD.freeze
    FONT SELECTION:
    Primary (Body/UI): [Sans name], Weights: 400, 600, 700
    Secondary (Headings): [Font name], Weights: 600, 700, 800
    Monospace (Code): [Mono], Weight: 400

    TYPE SCALE (Major Third 1.250):
    Display: 64/72/-0.02em
    H1: 48/56/-0.01em
    H2: 36/44/-0.01em
    H3: 28/36/0
    H4: 22/30/0
    Body Large: 18/28/0
    Body: 16/24/0
    Body Small: 14/20/0.01em
    Caption: 12/16/0.01em

    VALIDATION:
    □ 1.25/1.333 ratio maintained?
    □ Line-height multi-line ready?
    □ Weights available?
    □ 45-75 chars/line?

    FORBIDDEN:
    ❌ >3 families; ❌ >4 weights/family; ❌ Body lh <1.4; ❌ Justified; ❌ ALL CAPS >3 words
  MD

  GESTALT = <<~MD.freeze
    PROXIMITY:
    Related: 8-16px; Unrelated: 24-48px (2-3×)

    SIMILARITY:
    Buttons: same height/radius/weight
    Icons: same size per context (nav 24px)

    FIGURE-GROUND:
    Primary: #171717 on #FFFFFF ≈15:1
    Secondary: #525252 on #FAFAFA ≈7:1
  MD

  COMPONENTS = <<~MD.freeze
    BUTTONS (Primary):
    H: 44 (mobile) / 40 (desktop), Pad: 16/24, Radius: 8, Font: 16/600
    Bg: #2563EB; Text: #FFF; Hover: #1D4ED8; Active: #1E40AF
    Disabled: #93C5FD; Focus: 2px #3B82F6 (offset 2px); Transition ≤300ms

    INPUTS:
    Text: H 44/40; Pad 12/16; Border 1 #D1D5DB; Radius 6; Font 16/400
    Placeholder #9CA3AF; Focus border #2563EB + shadow 0 0 0 3 rgba(37,99,235,.1)
  MD

  ACCESSIBILITY = <<~MD.freeze
    CONTRAST (WCAG 2.1 AA):
    Text <18px: ≥4.5:1; Large (≥18px or ≥14px bold): ≥3:1; UI: ≥3:1

    TOUCH TARGETS:
    Mobile ≥44×44; Desktop ≥40×40; Spacing ≥8px

    FOCUS:
    Visible on ALL interactives, 2px outline + 2px offset; ≥3:1 contrast
  MD
end

module Spinner
  FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

  def self.wrap(msg = "Working", interval: 0.1)
    print "#{msg} "
    spinning = true

    t = Thread.new do
      i = 0
      while spinning
        print "\r#{msg} #{FRAMES[i % FRAMES.size]}"
        i += 1
        sleep interval
      end
    end
    yield
  ensure
    spinning = false
    t.join
    print "\r\e[2K#{msg} ✔\n"
  end
end

class CodeTransformer
  def self.transform(code)
    code.gsub!(/if\s+!\s*(.+?)$/, 'unless \1')
    seen = Hash.new(0)

    code = code.lines.reject do |line|
      normalized = line.strip
      is_skippable = normalized.empty? || normalized.start_with?("#", "//", "/*")
      next false if is_skippable
      seen[normalized] += 1
      seen[normalized] > 3
    end.join

    code.gsub!(/(?:gap|padding|margin|border-spacing):\s*(\d+)px/) do |match|
      value = $1.to_i
      nearest = Config::DesignSystem::SPACING_SCALE.min_by { |space| (space - value).abs }
      match.sub(/\d+/, nearest.to_s)
    end
    code
  end

  def self.audit(code)
    issues = []
    code.lines.each_with_index do |line, i|
      issues << "Line #{i + 1}: Ternary operator found" if Config::Policy::FORBID_TERNARY && line.match?(/\?.*:/) && !line.strip.start_with?("#")
      issues << "Line #{i + 1}: Exceeds max length of #{Config::Policy::MAX_LINE_LENGTH}" if line.length > Config::Policy::MAX_LINE_LENGTH
      if line.match(/color:\s*(#[0-9a-f]{6});.*background.*:\s*(#[0-9a-f]{6})/i)
        fg, bg = $1, $2
        ratio = calculate_contrast(fg, bg)
        if ratio < Config::DesignSystem::CONTRAST_MIN_RATIO
          issues << "Line #{i + 1}: Low contrast ratio (#{ratio.round(2)}:1) for #{fg} on #{bg}"
        end
      end
    end
    issues
  end

  def self.calculate_luminance(hex)
    rgb = hex.match(/#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})/i).captures.map { |c| c.to_i(16) / 255.0 }
    srgb = rgb.map { |c| c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    0.2126 * srgb[0] + 0.7152 * srgb[1] + 0.0722 * srgb[2]
  end

  def self.calculate_contrast(hex1, hex2)
    l1 = calculate_luminance(hex1)
    l2 = calculate_luminance(hex2)
    lighter, darker = [l1, l2].max, [l1, l2].min
    (lighter + 0.05) / (darker + 0.05)
  end
end

class MasterFormatter
  def initialize
    @prompt = TTY::Prompt.new(interrupt: :exit)
  end

  def run
    display_banner if Config::Policy::SHOW_BANNER
    loop do
      case @prompt.select("Select action:", menu_items, cycle: true)
      when :format then handle_file_processing(:format)
      when :audit then handle_file_processing(:audit)
      when :prompts then show_prompts
      when :export then export_prompt
      when :exit then break
      end
    end
  end

  private

  def menu_items
    { "Format files" => :format, "Audit files" => :audit, "View prompt library" => :prompts, "Export prompt to file" => :export, "Exit" => :exit }
  end

  def display_banner
    hostname = `hostname`.strip
    user = ENV["USER"] || ENV["USERNAME"] || "unknown"
    puts "** master.rb v#{Config::Meta::VERSION} (Ruby #{RUBY_VERSION}) **"
    puts "#{Config::Meta::UPDATED} UTC"
    puts "#{user}@#{hostname}:#{Dir.pwd}"
  end

  def handle_file_processing(mode)
    files = select_files(mode)
    return if files.empty?
    files.each { |file| process_file(file, mode) }
  end

  def select_files(mode)
    pattern = "**/*.{#{Config::Tools::FILE_EXTENSIONS.join(',')}}"
    all_files = Dir.glob(pattern)
    filtered_files = all_files.reject { |f| f.match?(/(node_modules|vendor|tmp|\.git)/) }
    if filtered_files.empty?
      @prompt.warn("No supported files found to #{mode}.")
      return []
    end
    @prompt.multi_select("Select files to #{mode}:", filtered_files, per_page: 15, filter: true)
  end

  def process_file(path, mode)
    content = File.read(path)
    if mode == :audit
      Spinner.wrap("Auditing #{path}") { @issues = CodeTransformer.audit(content) }
      if @issues.empty?
        @prompt.ok "✓ #{path}: No issues found."
      else
        @prompt.warn "✗ #{path}: #{@issues.size} issues found."
        @issues.each { |issue| puts "  #{issue}" }
      end
    else
      transformed_content = nil
      Spinner.wrap("Formatting #{path}") { transformed_content = CodeTransformer.transform(content) }
      if content != transformed_content
        File.write(path, transformed_content)
        run_external_tool(path)
        @prompt.ok "✓ Formatted #{path}"
      else
        @prompt.say "○ #{path}: No changes needed."
      end
    end
  end

  def run_external_tool(path)
    ext = File.extname(path)[1..].to_sym
    cmd = Config::Tools::EXTERNAL_TOOLS[ext]
    return unless cmd
    tool_name = cmd.split.first
    return unless system("command -v #{tool_name} >/dev/null 2>&1")
    Spinner.wrap("Running #{tool_name}") { system("#{cmd} #{path} 2>/dev/null") }
  end

  def show_prompts
    key = pick_prompt_key
    return unless key
    text = Prompts.const_get(key)
    @prompt.say("\n" + text + "\n")
  end

  def export_prompt
    key = pick_prompt_key
    return unless key
    text = Prompts.const_get(key)
    fname = @prompt.ask("Filename to write (e.g., #{key.to_s.downcase}.md):", default: "#{key.to_s.downcase}.md")
    return unless fname && !fname.strip.empty?
    Spinner.wrap("Writing #{fname}") { File.write(fname, text) }
    @prompt.ok "Wrote #{fname}"
  end

  def pick_prompt_key
    keys = {
      "Breakpoints & Validation" => :BREAKPOINTS,
      "Typography System" => :TYPOGRAPHY,
      "Gestalt Principles" => :GESTALT,
      "Component System" => :COMPONENTS,
      "Accessibility (WCAG)" => :ACCESSIBILITY,
    }
    @prompt.select("Select prompt:", keys, filter: true)
  end
end

if $PROGRAM_NAME == __FILE__
  MasterFormatter.new.run
end