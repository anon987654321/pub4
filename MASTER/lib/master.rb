# frozen_string_literal: true

require "json"
require "timeout"
require "zeitwerk"
require "yaml"
require_relative "security_error"

begin
  require "openssl"
rescue LoadError => e
  warn "openssl: #{e.message} — LLM calls fail"
end

module Master
  # Constitutional automation runtime and governed repository-work pipeline.
  ROOT = File.expand_path("..", __dir__).freeze
  REPO_ROOT = File.expand_path("..", ROOT).freeze
  OPENBSD_ROOT = File.join(REPO_ROOT, "OPENBSD").freeze
  RAILS_ROOT = File.join(REPO_ROOT, "RAILS").freeze
  DEPLOY_ROOT = OPENBSD_ROOT.freeze
  DEPLOY_RAILS = RAILS_ROOT.freeze
  TOOLS_ROOT = File.join(ROOT, "tools").freeze
  DATA = File.join(ROOT, "data").freeze
  COUNCIL_PATH = File.join(DATA, "council.yml").freeze
  RULES_PATH = File.join(DATA, "rules.yml").freeze
  BOOTSTRAP_AUTHORITY_FILES = [
    ["soul", "data/soul.yml"], ["rules", "data/rules.yml"], ["style", "data/style.yml"],
    ["voice", "data/voice.yml"], ["limits", "data/limits.yml"], ["orders", "data/state.yml"],
    ["playbook", "data/patterns.yml"], ["principles", "data/operator_principles.yml"],
    ["skills", "data/patterns.yml"], ["context", "data/project_context.yml"],
    ["operator", "../OPENBSD/RUNBOOK.md"],
  ].freeze

  BUNDLE_BIN = RUBY_PLATFORM.include?("openbsd") ? "bundle34" : "bundle"
  MIN_API_KEY_LENGTH_HEURISTIC = 20
  MAX_CONSTITUTION_BYTES = 10 * 1024 * 1024
  YAML_LOAD_TIMEOUT_S = 5
  OPENROUTER_DEFAULT = "z-ai/glm-4.5-air:free"
  # First slug in models.grok_primary — verified working on OpenRouter :free pool (2026-07-11).
  FREE_PRIMARY_MODEL = "nvidia/nemotron-3-super-120b-a12b:free"
  SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze
  DEFAULT_CONTEXT_WINDOW = 128_000
  CTX_WINDOW_SIZE = DEFAULT_CONTEXT_WINDOW
  VIOLATION_TRUNCATE = 90

  FILE_LANGUAGE_MAP = {
    ".rb" => "ruby", ".rake" => "ruby", ".gemspec" => "ruby",
    ".yml" => "yaml", ".yaml" => "yaml", ".json" => "json",
    ".js" => "javascript", ".ts" => "javascript", ".jsx" => "javascript", ".tsx" => "javascript",
    ".sh" => "zsh", ".zsh" => "zsh", ".bash" => "zsh", ".md" => "markdown",
    ".html" => "html", ".htm" => "html", ".erb" => "html", ".css" => "css",
    ".scss" => "scss", ".sass" => "scss",
  }.freeze

  # NUL-byte sniff on the first 4KB. Errs on the side of "binary" so scanners
  # skip unreadable files instead of choking on them. Module function, not a
  # File monkeypatch — core classes stay untouched (PoLA).
  def self.binary_file?(path)
    return false unless File.file?(path)

    chunk = File.open(path, "rb") { |io| io.read(4096) } || ""
    chunk.include?("\x00")
  rescue StandardError => e
    warn("binary_check: #{path}: #{e.message}")
    true
  end

  def self.repo_root = REPO_ROOT
  def self.operator_path(*parts) = File.join(OPENBSD_ROOT, *parts)
  def self.rails_path(*parts) = File.join(RAILS_ROOT, *parts)
  def self.openbsd_path(*parts) = File.join(OPENBSD_ROOT, *parts)
  def self.deploy_path(*parts) = operator_path(*parts)
  def self.tool_path(*parts) = File.join(TOOLS_ROOT, *parts)
  def self.data_path(*parts) = File.join(DATA, *parts)
  # The one reader of data/rules.yml. A missing section raises rather than
  # returning {}, because data_file answers a missing file with a path to it and
  # every caller reads the empty result as a law with nothing in it.
  def self.law(section, root: ROOT)
    path = File.join(root, "data", "rules.yml")
    mtime = File.mtime(path)
    @law = nil unless @law_stamp == [path, mtime]
    @law ||= (load_yaml(path, default: {}) || {}).tap { @law_stamp = [path, mtime] }
    @law.fetch(section.to_s) { raise KeyError, "data/rules.yml has no #{section}: section" }
  end

  def self.limits_path = data_file("limits.yml", "workflow.yml")
  def self.state_path = data_file("state.yml", "standing_orders.yml")

  def self.data_file(*names)
    names.each do |name|
      path = data_path(name)
      return path if File.exist?(path)
    end
    data_path(names.first)
  end

  def self.flatten_rules(body)
    return body.values.flatten if body.is_a?(Hash)
    return body if body.is_a?(Array)

    []
  end

  def self.rule_count(root: ROOT)
    flatten_rules(load_rules(root:).fetch("rules", {})).count do |rule|
      rule.is_a?(Hash) && !rule["id"].to_s.strip.empty?
    end
  rescue StandardError => e
    warn("rule_count: #{e.message}")
    0
  end

  def self.authority_paths(root: ROOT)
    BOOTSTRAP_AUTHORITY_FILES.filter_map do |label, relative|
      path = File.expand_path(relative, root)
      [label, path] if File.exist?(path)
    end
  end

  loader = Zeitwerk::Loader.new
  loader.push_dir(__dir__, namespace: Master)
  loader.ignore(__FILE__)
  loader.inflector.inflect(
    "cli" => "CLI", "llm" => "LLM", "llm_dispatcher" => "LLMDispatcher",
    "mcp_server" => "MCPServer", "mcp_coordinator" => "McpCoordinator",
    "diff_stager" => "DiffStager", "code_index" => "CodeIndex", "git_context" => "GitContext",
    "ast_edit" => "AstEdit", "rule_dsl" => "RuleDSL", "tts" => "TTS",
    "pwa_audit" => "PwaAudit", "mobile_pwa_operator" => "MobilePwaOperator"
  )
  loader.enable_reloading if defined?(MASTER_DEV_MODE) || ENV["MASTER_DEV"].to_s == "1"

  # data/autoload.yml lists what Zeitwerk must not load, grouped by why. This
  # was five lists in this file with no reason recorded against any entry, so
  # adding a file under lib/cli/cli/ broke boot with an error that did not
  # explain itself. `rake lint:autoload` proves every entry is still necessary.
  def self.autoload_ignores(root: ROOT)
    YAML.safe_load_file(File.join(root, "data", "autoload.yml")).fetch("autoload").values.flatten
  end

  autoload_ignores.each { |relative| loader.ignore(File.join(__dir__, relative)) }

  loader.setup
  LOADER = loader

  require_relative "boot/boot"
  extend MasterData
  extend MasterRuntime
  extend MasterBoot

  require_relative "unwrap_error"

  def self.eager_load! = LOADER.eager_load

  def self.const_missing(symbol)
    return Review::Agent if symbol == :Agent

    super
  end
end
