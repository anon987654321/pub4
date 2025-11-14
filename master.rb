#!/usr/bin/env ruby
# frozen_string_literal: true

# encoding: UTF-8

#

# master.rb v120.2.0

# Self-optimizing formatter/auditor with autoiterative convergence.

#

# LLM CONTRACT:

#  • Canonical: discard older versions.

#  • Reply: unified git diff + ≤2 sentence note.

#  • No changes: emit "(no changes)".

#  • On approval keywords (approve/ship/merge): append full final files.

#  • Safety: no destructive ops out-of-scope → TODO comment.

#  • Deterministic: avoid random values unless requested.

begin
  require "tty-prompt"

rescue LoadError

  warn "[warn] tty-prompt gem recommended: gem install --user-install tty-prompt"

end

require "fileutils"
require "tempfile"

CONFIG = {
  meta: {

    version: "120.2.0",

    updated: "2025-11-10 22:47:12",

    owner: "anon987654321",

    note: "Single source of truth. Hybrid v120.1.0 + v97.7.0 improvements."

  },

  runtime: {

    dry: ARGV.include?("--dry"),

    log_level: ARGV.include?("--silent") ? "silent" : (ARGV.include?("--summary") ? "summary" : "verbose"),

    self_update: ARGV.include?("--self-update"),

    max_iter: 15,

    lockfile: "/tmp/master_rb_#{ENV['USER'] || 'user'}.lock",

    approval_keywords: %w[approve approved ship merge finalize]

  },

  policy: {

    forbid_ternary: true,

    forbid_concat: true,

    show_banner: true,

    max_line_length: 120,

    max_method_lines: 20,

    max_nesting: 2,

    no_magic_numbers: false,

    prefer_named_functions: true

  },

  design: {

    spacing_scale: [4, 8, 12, 16, 24, 32, 48, 64],

    contrast_min: 4.5,

    touch_target_min: 44,

    focus_outline_width: 2,

    animation_base: 200,

    border_radius: [0, 2, 4, 6, 8, 12, 16, 24]

  },

  principles: {

    dry: "Extract repetition, no duplication > 70% similarity",

    kiss: "Simplicity over cleverness",

    yagni: "Delete speculation, no unused code",

    srp: "One reason to change per module",

    minimize: "Fewest files, shortest code, clearest names",

    shallow: "Max 2 nesting levels",

    economic: "ROI > 1.25x for any change"

  },

  paths: {

    shell: "zsh.exe",

    tree_sh: "./sh/tree.sh",

    clean_sh: "./sh/clean.sh"

  },

  vps: {

    user: "dev",

    ip: "185.52.176.18",

    port: "31415",

    host: "server27.openbsd.amsterdam"

  },

  tools: {

    external: {

      rb: "rubocop -a",

      js: "prettier --write",

      ts: "prettier --write",

      html: "prettier --write",

      css: "prettier --write",

      sh: "shfmt -w -i 2",

      zsh: "shfmt -w -i 2"

    },

    exts: %w[rb js ts html css scss sh zsh rs json]

  },

  patterns: {

    inline_comment: /(\S) {2,}(#)/,

    constant_assign: /^(\s*[A-Z][A-Z0-9_]*)\s+=\s*/,

    ternary: /\?.*:/,

    string_concat: /\+\s*["']/

  },

  zsh: {

    philosophy: "No external forks, pure zsh parameter expansion",

    banned: %w[awk sed tr grep cut head tail uniq sort wc cat echo find bash sh perl python],

    replacements: {

      awk: "zsh array/string ops",

      sed: "${var//find/replace}",

      grep: "${(M)arr:#*pattern*}",

      cat: "$(<file)",

      echo: "print"

    }

  },

  prompts: {

    breakpoints: "sm:640px md:768px lg:1024px xl:1280px 2xl:1536px",

    typography: "Scale 1.25: 64/48/36/28/22/18/16/14/12, lh≥1.4",

    gestalt: "Proximity: 8-16px related, 24-48px unrelated",

    components: "Button: H44/40, Pad16/24, Radius8, Focus2px",

    accessibility: "Contrast: ≥4.5:1 text, ≥3:1 UI, Touch≥44px"

  },

  creative: {

    exceed_expectations: true,

    think_beyond_literal: true,

    optimize_wow: true,

    iterate_until_astonishing: true

  }

}.freeze

module Logger
  COLORS = {

    info: "\e[34m", warn: "\e[33m", error: "\e[31m",

    fix: "\e[32m", done: "\e[35m", debug: "\e[90m", reset: "\e[0m"

  }.freeze

  def self.log(level, msg)
    ll = CONFIG[:runtime][:log_level]

    return if ll == "silent"

    return if ll == "summary" && level == :debug

    ts = Time.now.utc.strftime("%H:%M:%S")

    color = COLORS[level] || COLORS[:reset]

    puts "#{color}[#{ts}] #{level} #{msg}#{COLORS[:reset]}"

  end

  %i[info warn error fix done debug].each do |m|
    define_singleton_method(m) { |msg| log(m, msg) }

  end

end

module Spinner
  FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

  def self.wrap(msg = "Working", interval: 0.1)
    return yield if CONFIG[:runtime][:log_level] == "silent"

    print "#{msg} "
    spinning = true

    result = nil

    thr = Thread.new do
      i = 0

      while spinning

        print "\r#{msg} #{FRAMES[i % FRAMES.size]}"

        i += 1

        sleep interval

      end

    end

    result = yield
  ensure

    spinning = false

    thr&.join

    print "\r\e[2K#{msg} ✔\n"

    result

  end

end

class CodeAudit
  def self.lum(hex)

    rgb = hex.match(/#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})/i).captures.map { |c| c.to_i(16) / 255.0 }

    srgb = rgb.map { |c| c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }

    0.2126 * srgb[0] + 0.7152 * srgb[1] + 0.0722 * srgb[2]

  end

  def self.contrast(a, b)
    l1 = lum(a)

    l2 = lum(b)

    hi = [l1, l2].max

    lo = [l1, l2].min

    (hi + 0.05) / (lo + 0.05)

  end

  def self.audit(code)
    issues = []

    code.each_line.with_index(1) do |line, i|

      next if line.strip.start_with?("#", "//", "/*")

      if CONFIG[:policy][:forbid_ternary] && line.match?(CONFIG[:patterns][:ternary])
        issues << "Line #{i}: ternary operator"

      end

      if line.length > CONFIG[:policy][:max_line_length]
        issues << "Line #{i}: exceeds max length (#{line.length})"

      end

      if line.match(/color:\s*(#[0-9a-f]{6}).*background.*:\s*(#[0-9a-f]{6})/i)
        fg = $1

        bg = $2

        ratio = contrast(fg, bg)

        if ratio < CONFIG[:design][:contrast_min]

          issues << "Line #{i}: low contrast #{ratio.round(2)}:1"

        end

      end

    end

    issues

  end

end

class Autoiterator
  attr_reader :path, :content, :iter, :fixes

  def initialize(path)
    @path = path

    @content = File.read(path)

    @iter = 0

    @fixes = 0

    @converged = false

  end

  def run
    Logger.info "autoiterator: #{@path}"

    lock do

      CONFIG[:runtime][:max_iter].times do

        @iter += 1

        issues = scan

        Logger.debug "iter #{@iter}: #{issues.size} issues"

        if issues.empty?
          @converged = true

          break

        end

        changed = fix_all unless CONFIG[:runtime][:dry]
        break unless changed

      end

      report
      write_back if @fixes > 0 && !CONFIG[:runtime][:dry]

    end

  end

  private
  def scan
    issues = []

    @content.each_line.with_index(1) do |line, i|

      issues << [:tab, i] if line.include?("\t")

      issues << [:semicolon, i] if line.include?(";") && !line.include?("frozen_string_literal")

      issues << [:long, i] if line.length > CONFIG[:policy][:max_line_length]

      next if line.strip.start_with?("#", "//")

      issues << [:ternary, i] if CONFIG[:policy][:forbid_ternary] && line.match?(CONFIG[:patterns][:ternary])

    end

    issues

  end

  def fix_all
    before = @content.dup

    @content.gsub!(/\t/, "  ")

    @content.gsub!(/;(?!.*frozen)/, "")

    @content.gsub!(/\n{3,}/, "\n\n")

    @content.gsub!(/if\s+!\s*(.+?)$/, 'unless \1')

    @content.gsub!(CONFIG[:patterns][:inline_comment], '\1 \2')

    @content.gsub!(CONFIG[:patterns][:constant_assign], '\1 = ')

    changed = @content != before

    @fixes += 1 if changed

    changed

  end

  def write_back
    backup = "#{@path}.bak.#{Time.now.to_i}.#{Process.pid}"

    FileUtils.cp(@path, backup)

    Logger.debug "backup: #{backup}"

    Tempfile.create(["master", File.extname(@path)]) do |tmp|
      tmp.write(@content)

      tmp.flush

      FileUtils.mv(tmp.path, @path)

    end

    Logger.fix "wrote: #{@path}"
  end

  def report
    if @converged

      Logger.done "converged in #{@iter} iteration#{@iter == 1 ? '' : 's'}"

    elsif CONFIG[:runtime][:dry]

      Logger.done "dry-run: #{@iter} iterations (no changes)"

    else

      Logger.done "#{@fixes} fixes in #{@iter} iteration#{@iter == 1 ? '' : 's'}"

    end

  end

  def lock
    lf = CONFIG[:runtime][:lockfile]

    File.open(lf, File::CREAT | File::EXCL | File::WRONLY) do |f|

      f.write(Process.pid)

      Logger.debug "lock acquired"

      yield

    end

  rescue Errno::EEXIST

    Logger.error "lock busy (another instance running)"

    exit 1

  ensure

    File.delete(lf) if File.exist?(lf)

    Logger.debug "lock released"

  end

end

class MasterFormatter
  def initialize

    @prompt = defined?(TTY::Prompt) ? TTY::Prompt.new(interrupt: :exit) : nil

  end

  def run
    banner if CONFIG[:policy][:show_banner]

    return self_update if CONFIG[:runtime][:self_update]

    @prompt ? interactive : cli_mode

  end

  private
  def banner
    return if CONFIG[:runtime][:log_level] == "silent"

    hostname = `hostname`.strip rescue "unknown"

    user = ENV["USER"] || ENV["USERNAME"] || "unknown"

    puts "\e[1m** master.rb v#{CONFIG[:meta][:version]} (Ruby #{RUBY_VERSION}) **\e[0m"

    puts "#{CONFIG[:meta][:updated]} UTC"

    puts "#{user}@#{hostname}:#{Dir.pwd}\n\n"

  end

  def interactive
    loop do

      action = @prompt.select("Action:", menu, cycle: true)

      case action

      when :format then batch_format

      when :audit then batch_audit

      when :view_config then view_config

      when :self_refactor then self_refactor

      when :self_update then self_update

      when :exit then break

      end

    end

  end

  def cli_mode
    Logger.info "CLI mode (install tty-prompt for interactive menu)"

    batch_format

    batch_audit

    self_refactor

  end

  def menu
    {

      "Format files" => :format,

      "Audit files" => :audit,

      "View config" => :view_config,

      "Self-refactor master.rb" => :self_refactor,

      "Self-update (git pull)" => :self_update,

      "Exit" => :exit

    }

  end

  def scan_files
    pattern = "**/*.{#{CONFIG[:tools][:exts].join(',')}}"

    Dir.glob(pattern).reject { |f| f.match?(%r{(^|/)(node_modules|vendor|tmp|\.git)(/|$)}) }

  end

  def batch_format
    files = scan_files

    return Logger.warn "no files found" if files.empty?

    files.each do |f|
      Autoiterator.new(f).run

      run_external_tool(f)

    end

  end

  def batch_audit
    files = scan_files

    return Logger.warn "no files found" if files.empty?

    files.each do |f|
      content = File.read(f)

      issues = CodeAudit.audit(content)

      if issues.empty?

        Logger.info "✓ #{f}: clean"

      else

        Logger.warn "✗ #{f}: #{issues.size} issues"

        issues.each { |i| puts " #{i}" }

      end

    end

  end

  def run_external_tool(path)
    ext = File.extname(path)[1..].to_sym

    cmd = CONFIG[:tools][:external][ext]

    return unless cmd

    tool = cmd.split.first
    return unless system("command -v #{tool} >/dev/null 2>&1")

    Spinner.wrap("#{tool} #{path}") { system("#{cmd} #{path} 2>/dev/null") }
  end

  def self_refactor
    Logger.info "self-refactoring master.rb..."

    Autoiterator.new(__FILE__).run

  end

  def self_update
    Logger.info "git pull origin main..."

    ok = system("git pull origin main")

    ok ? Logger.done("updated") : Logger.error("update failed")

  end

  def view_config
    puts "\n" + "=" * 60

    puts "MASTER.RB CONFIGURATION v#{CONFIG[:meta][:version]}"

    puts "=" * 60

    CONFIG.each do |section, values|

      puts "\n#{section.to_s.upcase}:"

      if values.is_a?(Hash)

        values.each { |k, v| puts " #{k}: #{v.inspect}" }

      else

        puts " #{values.inspect}"

      end

    end

    puts "\n" + "=" * 60 + "\n"

    @prompt&.keypress("Press any key to continue...")

  end

end

module MasterContract
  def self.canonical?

    true

  end

  def self.approval?(text)
    words = text.downcase.split

    (CONFIG[:runtime][:approval_keywords] & words).any?

  end

end

if $PROGRAM_NAME == __FILE__
  MasterFormatter.new.run

end

