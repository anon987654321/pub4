# frozen_string_literal: true

require "json"
require "timeout"
require "zeitwerk"
require "yaml"
require_relative "security_error"
require_relative "trace/dmesg"

begin
  require "openssl"
rescue LoadError => e
  Master::Trace::Dmesg.status("crypto0", "#{e.message}, LLM calls fail", io: $stderr)
end

module Master
  # Constitutional automation runtime and governed repository-work pipeline.
  VERSION = File.read(File.expand_path("../../VERSION", __dir__), encoding: "UTF-8").strip.freeze
  ROOT = File.expand_path("..", __dir__).freeze
  REPO_ROOT = File.expand_path("..", ROOT).freeze
  OPENBSD_ROOT = File.join(REPO_ROOT, "OPENBSD").freeze
  RAILS_ROOT = File.join(REPO_ROOT, "RAILS").freeze
  DATA = File.join(ROOT, "data").freeze
  COUNCIL_PATH = File.join(DATA, "council.yml").freeze
  LAWS_PATH = File.join(DATA, "laws.yml").freeze

  BUNDLE_BIN = RUBY_PLATFORM.include?("openbsd") ? "bundle40" : "bundle"
  MIN_API_KEY_LENGTH_HEURISTIC = 20
  MAX_CONSTITUTION_BYTES = 10 * 1024 * 1024
  YAML_LOAD_TIMEOUT_S = 20
  # The OpenRouter default and :free-pool head are Master.openrouter_default
  # and Master.free_primary_model (boot/runtime.rb) — readers of providers.yml
  # and models.yml through the sanctioned loaders. They were constants here,
  # hand-copied from the yml, until the 2026-08-18 registry fix had to edit
  # three copies of one slug in step.
  SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze
  DEFAULT_CONTEXT_WINDOW = 128_000
  VIOLATION_TRUNCATE = 90

  FILE_LANGUAGE_MAP = {
    ".rb" => "ruby", ".rake" => "ruby", ".gemspec" => "ruby", ".ru" => "ruby",
    ".yml" => "yaml", ".yaml" => "yaml", ".json" => "json",
    ".js" => "javascript", ".mjs" => "javascript", ".ts" => "javascript",
    ".jsx" => "javascript", ".tsx" => "javascript",
    ".sh" => "zsh", ".zsh" => "zsh", ".bash" => "zsh", ".ksh" => "zsh", ".md" => "markdown",
    ".html" => "html", ".htm" => "html", ".erb" => "html", ".css" => "css",
    ".scss" => "scss", ".sass" => "scss"
  }.freeze

  # A Ruby file need not end in .rb, and an extension-only map calls every one
  # of these unknown. 94 tracked files are in that position — Gemfile, Rakefile,
  # and every executable under bin/ whose language lives in its shebang.
  NAMED_LANGUAGES = {
    "Gemfile" => "ruby", "Rakefile" => "ruby", "Guardfile" => "ruby",
    "Capfile" => "ruby", "Brewfile" => "ruby", "Podfile" => "ruby",
    "Vagrantfile" => "ruby", "config.ru" => "ruby"
  }.freeze

  SHEBANG_LANGUAGES = { /\bruby\b/ => "ruby", /\b(?:zsh|bash|ksh|sh)\b/ => "zsh" }.freeze

  # One answer to "what language is this file", because two answers is how a
  # rule comes to mean different things in two engines. Rule#applies_to? asks
  # `lang && languages.include?(lang)` and Law#applies? asked
  # `language.nil? || ...` — so an unresolved file satisfied every
  # language-scoped law while satisfying no language-scoped registry rule. That
  # let .gitignore, .svg, .toml and .env be told to carry a Ruby magic comment:
  # of 176 FROZEN_STRING_LITERAL findings, 4 were on Ruby files.
  #
  # Extension first because it is free and covers 3,876 of 4,272 tracked files.
  # The name and the shebang are the fallbacks, and the shebang is a read, so
  # the answer is memoised: the scanner asks this once per rule per file.
  def self.language_for(path)
    @language_for ||= {}
    key = path.to_s
    stat = File.stat(key) if File.file?(key)
    stamp = stat && [stat.size, stat.ino, stat.mtime.to_r]
    cached = @language_for[key]
    return cached[:language] if cached && cached[:stamp] == stamp

    language = resolve_language(key)
    @language_for[key] = { stamp:, language: }
    language
  end

  def self.resolve_language(path)
    by_ext = FILE_LANGUAGE_MAP[File.extname(path).downcase]
    return by_ext if by_ext

    named = NAMED_LANGUAGES[File.basename(path)]
    return named if named

    shebang_language(path)
  end

  # Only the first line, and only when it is a shebang. A file that opens with
  # anything else has nothing to say about its language here.
  def self.shebang_language(path)
    return unless File.file?(path)

    first = File.open(path) { |io| io.gets.to_s }
    return unless first.start_with?("#!")

    match = SHEBANG_LANGUAGES.find { |pattern, _lang| pattern.match?(first) }
    match&.last
  rescue SystemCallError, IOError
    nil
  end
  private_class_method :resolve_language, :shebang_language

  # NUL-byte sniff on the first 4KB. Errs on the side of "binary" so scanners
  # skip unreadable files instead of choking on them. Module function, not a
  # File monkeypatch — core classes stay untouched (PoLA).
  def self.binary_file?(path)
    return false unless File.file?(path)

    chunk = File.open(path, "rb") { |io| io.read(4096) } || ""
    chunk.include?("\x00")
  rescue StandardError => e
    warn("binary0: #{path}, #{e.message}")
    true
  end

  def self.repo_root = REPO_ROOT
  # File.exist?, never File.directory?. A `git worktree` checkout carries .git as
  # a file holding a gitdir line, and CLAUDE.md tells every agent here to take
  # one — so a directory test answers no for the trees the runtime mostly runs
  # in. It disabled rollback after a failed fix, dropped the branch and sha from
  # every snapshot, and reported the boot receipt degraded on a capability the
  # process had.
  def self.git_checkout?(root = REPO_ROOT) = File.exist?(File.join(root, ".git"))
  def self.data_path(*parts) = File.join(DATA, *parts)
  def self.models_config(root: ROOT)
    load_yaml(File.join(root, "data", "models.yml")) || {}
  end

  def self.patterns_config(root: ROOT)
    load_yaml(File.join(root, "data", "patterns.yml")) || {}
  end

  def self.soul_config(root: ROOT)
    load_yaml(File.join(root, "data", "soul.yml")) || {}
  end


  # The one reader of data/laws.yml. A missing section raises rather than
  # returning {}, because every caller reads the empty result as a law with nothing in it.
  def self.law_entries(root: ROOT)
    data = load_laws(root:) || {}
    legacy = data["laws"]
    if legacy.is_a?(Hash)
      return legacy.filter_map { |id, value| value.merge("id" => id.to_s) if value.is_a?(Hash) }
    end

    data.filter_map do |id, value|
      next unless value.is_a?(Hash) && value["priority"] && value["statement"]
      value.merge("id" => id.to_s)
    end
  end

  def self.law(section, root: ROOT)
    data = load_laws(root:)
    data.fetch(section.to_s) { raise KeyError, "data/laws.yml has no #{section}: section" }
  end

  # The one reader of data/agent_taxonomy.yml. It had three, each building the
  # path its own way — File.join(ROOT, "data", ...), data_path, and a keyword
  # default on AgentPool — which is the shape reader_singularity exists to catch:
  # they all called load_yaml, so "bypasses the helper" would have missed it.
  # Answers {} on a missing file, because every caller already reads a missing
  # taxonomy as "no declared types" and falls back to its own constants.
  def self.agent_taxonomy(root: ROOT)
    load_yaml(File.join(root, "data", "agent_taxonomy.yml")) || {}
  end

  # The design blocks are rules like any other now: `tier: design` with the old
  # nested section under `config`. This rebuilds the map they used to form, so
  # everything that dug design_rules by block name still reaches its key.
  def self.tokens(root: ROOT)
    (load_laws(root:) || {})["tokens"] || {}
  end


  # One path into it, so a key that moves breaks in one place rather than in the
  # nineteen files that each dug the section themselves:
  # `Master.design("layout_rules", "touch", "target_min_px")`.
  def self.design(*path, root: ROOT)
    config = tokens(root:)
    path.empty? ? config : config.dig(*path.map(&:to_s))
  end

  def self.limits_path = data_path("limits.yml")
  def self.state_path = data_path("state.yml")

  def self.flatten_rules(body)
    return body.values.flatten if body.is_a?(Hash)
    return body if body.is_a?(Array)

    []
  end

  def self.rule_count(root: ROOT)
    law_entries(root:).count do |rule|
      rule.is_a?(Hash) && !rule["id"].to_s.strip.empty?
    end
  rescue StandardError => e
    warn("rule0: count failed, #{e.message}")
    0
  end

  require_relative "ai/operator_contract"
  # operator/ is intentionally outside Zeitwerk because most of it defines the
  # foreign top-level Operator namespace; Mode is the one Master-owned operator
  # contract used by the interactive fold path, so load it explicitly.
  require_relative "operator/mode"

  loader = Zeitwerk::Loader.new
  loader.push_dir(__dir__, namespace: Master)
  loader.ignore(__FILE__)
  loader.inflector.inflect(
    "ai" => "AI", "cli" => "CLI", "llm" => "LLM", "llm_dispatcher" => "LLMDispatcher",
    "mcp_server" => "MCPServer", "mcp_coordinator" => "McpCoordinator",
    "diff_stager" => "DiffStager", "code_index" => "CodeIndex", "git_context" => "GitContext",
    "ast_edit" => "AstEdit", "law_dsl" => "LawDSL", "constraint_dsl" => "ConstraintDSL", "tts" => "TTS", "md" => "MD", "pdf" => "PDF"
  )
  loader.enable_reloading if defined?(MASTER_DEV_MODE) || ENV["MASTER_DEV"].to_s == "1"

  # data/autoload.yml lists what Zeitwerk must not load, grouped by why. This
  # was five lists in this file with no reason recorded against any entry, so
  # adding a file under a directory whose parts reopen one class broke boot
  # with an error that did not
  # explain itself. `rake lint:autoload` proves every entry is still necessary.
  def self.autoload_ignores(root: ROOT)
    YAML.safe_load_file(File.join(root, "data", "autoload.yml")).fetch("autoload").values.flatten
  end

  autoload_ignores.each { |relative| loader.ignore(File.join(__dir__, relative)) }

  loader.setup
  LOADER = loader

  require_relative "boot/paths"
  require_relative "boot/data"
  require_relative "boot/runtime"
  require_relative "boot/master_boot"
  extend DataLoading
  extend MasterRuntime
  extend MasterBoot

  require_relative "unwrap_error"

  def self.eager_load! = LOADER.eager_load
end
