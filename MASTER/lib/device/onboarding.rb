# frozen_string_literal: true

require "fileutils"
require_relative "../boot/paths"

module Master
  module Device
    # The first boot on a host prints what is in place and what is missing,
    # each missing piece with the one line that fixes it, in the boot's dmesg
    # voice. A phone gets the Termux checks as well. Nothing here installs,
    # prompts or waits: the face's ear is Device::Setup's, on its own thread,
    # and a check that raises becomes a line rather than a failed boot.
    class Onboarding
      # says is the whole line after the device name, the fix included when
      # the check failed, so a later boot prints a failure unchanged.
      Check = Data.define(:name, :ok, :says) do
        def self.of(name, ok, present, missing) = new(name, ok, ok ? present : missing)
      end

      MARK = MasterPaths.state("onboarded")
      ENV_FILE = File.expand_path("~/.config/master/env")
      REPO_URL = "https://github.com/anon987654321/pub4"
      # The order a lane is preferred in when several keys are set; the
      # variable names each provider reads stay in data/providers.yml.
      LANE_ORDER = %w[openrouter anthropic openai gemini xai deepseek mistral replicate].freeze
      BUILD_TOOLS = %w[clang make pkg-config].freeze
      # What bundle install needs on Termux before it can build the native
      # gems, and the flag that links sqlite3 against pkg's libsqlite. The
      # Gemfile sets the flag itself; the line stays for a stale checkout.
      TERMUX_BUNDLE = "pkg install build-essential sqlite && bundle config set build.sqlite3 " \
                      "--enable-system-libraries && bundle install"
      TEMPLATE = <<~ENV
        # MASTER reads this file at boot. One KEY=value per line; # starts a comment.
        # Uncomment one key and paste your own value. MASTER never writes a key here.
        #
        # One key is enough. With none, MASTER answers through LLM7's keyless free tier.
        # OPENROUTER_API_KEY=   https://openrouter.ai/keys, free models included
        # GEMINI_API_KEY=       https://aistudio.google.com/apikey, free tier
        # ANTHROPIC_API_KEY=
        # OPENAI_API_KEY=
        # XAI_API_KEY=
        # DEEPSEEK_API_KEY=
        # REPLICATE_API_TOKEN=
        # GROQ_API_KEY=         free signup, joins the free lane
        #
        # A local model needs no key: pkg install ollama, ollama serve &, ollama pull qwen3.5:0.8b
      ENV

      # Gems the lockfile names that this Ruby cannot load, for bin/master to
      # refuse with a fix line before the runtime raises LoadError mid-boot.
      # Git-sourced gems live under bundler's own path and are left out.
      def self.missing_gems(lockfile)
        section = File.read(lockfile)[/^DEPENDENCIES\n(.*?)(?:\n\n|\z)/m, 1].to_s
        wanted = section.lines.map(&:strip).reject { |line| line.empty? || line.include?("!") }
        wanted.map { |line| line.split.first }.reject do |name|
          Gem::Specification.find_all_by_name(name).any? { |spec| !spec.missing_extensions? }
        end
      end

      # Only at an interactive boot: a pipe, a test or the daemon gets nothing.
      def self.run!(env: ENV, out: $stderr, tty: $stdin.tty?)
        return unless tty
        return if env["MASTER_IN_PROOF"] == "1" || env["MASTER_ONBOARD"] == "0"

        new(env:, out:).run
      rescue StandardError => e
        out.puts("onboard0: skipped — #{e.class}: #{e.message}")
      end

      def initialize(env: ENV, out: $stderr, android: Device.android?, mark: MARK, env_file: ENV_FILE,
                     which: ->(cmd) { Master::Voice::Playback.which(cmd) }, root: MasterPaths.root,
                     git: ->(key) { IO.popen(["git", "config", key], err: File::NULL, &:read).strip })
        @env = env
        @out = out
        @android = android
        @mark = mark
        @env_file = env_file
        @which = which
        @root = root
        @git = git
      end

      def first_run? = !File.exist?(@mark)

      # The checklist on a first run; afterwards only what is still missing.
      def run
        first = first_run?
        created = ensure_env_file
        @out.puts("onboard0: first run on this #{@android ? "phone" : "host"}") if first
        @out.puts("env0: created #{home(@env_file)}, comments only; uncomment one key there") if created
        @out.puts("pair0: this phone is not personal yet — say /pair owner [name] to pair it to yourself") if @android && !Device::Agent.paired?(root: @root)
        checks.each { |check| @out.puts("#{check.name}0: #{check.says}") if first || !check.ok }
        mark! if first
      end

      def checks
        [*(@android ? termux_checks : []), lane_check, git_check]
      end

      # The best lane this host reaches now: a provider key, then a local
      # model, then the keyless free tier the router asks when nothing is set.
      def lane
        LANE_ORDER.each do |name|
          variable = Array(Master.provider_config.dig(name, "env")).find { |var| key?(@env[var]) }
          return [name, variable] if variable
        end
        return ["ollama", nil] if @which.call("ollama")

        ["llm7", nil]
      end

      # Writes the commented template once; an existing file is never touched,
      # and EXCL makes a file another session created meanwhile raise rather
      # than be overwritten.
      def ensure_env_file
        return false if File.exist?(@env_file)

        FileUtils.mkdir_p(File.dirname(@env_file), mode: 0o700)
        File.open(@env_file, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(TEMPLATE) }
        true
      end

      private

      def termux_checks
        [
          Check.of(:ruby, RUBY_VERSION >= "3.4", "ruby #{RUBY_VERSION}",
                   "ruby #{RUBY_VERSION} is older than 3.4 — pkg upgrade ruby"),
          Check.of(:build, BUILD_TOOLS.all? { |cmd| @which.call(cmd) }, "clang, make and pkg-config present",
                   "no compiler for native gems — pkg install build-essential"),
          Check.of(:sqlite, sqlite?, "sqlite3 gem loads",
                   "sqlite3 gem missing — cd #{home(@root)} && #{TERMUX_BUNDLE}"),
          Check.of(:termux, @which.call("termux-media-player"), "Termux:API present",
                   "no speaker, mic or sensors — install the Termux:API app, then pkg install termux-api"),
          Check.new(:ear, true, "#{Setup.new(env: @env).progress}; set up in the background"),
          checkout_check,
        ]
      end

      # Android's shared storage takes no execute bit, so bin/master cannot run
      # from a checkout there; termux-setup-storage only links it into ~/storage.
      def checkout_check
        Check.of(:checkout, !@root.start_with?("/storage/", "/sdcard/"), "checkout at #{home(@root)}",
                 "#{@root} is shared storage, which takes no execute bit — git clone #{REPO_URL} ~/pub4")
      end

      # A keyless boot still answers, so the free tier is not a failure; the
      # line says how to reach a better model, on the first run only.
      def lane_check
        name, variable = lane
        better = "set OPENROUTER_API_KEY in #{home(@env_file)}"
        better += ", or #{Master.local_model_install_hint}" if @android
        says = case name
               when "llm7" then "no key, answering through LLM7's keyless free tier — #{better}"
               when "ollama" then "local ollama, no key"
               else "#{name} via #{variable}"
               end
        Check.new(:model, true, says)
      end

      def git_check
        named = !@git.call("user.name").empty? && !@git.call("user.email").empty?
        Check.of(:git, named, "identity set for /commit",
                 'no identity for /commit — git config --global user.name "Your Name"; ' \
                 "git config --global user.email you@example.com")
      end

      def sqlite?
        require "sqlite3"
        true
      rescue LoadError
        false
      end

      def key?(value) = value.to_s.length >= Master::MIN_API_KEY_LENGTH_HEURISTIC

      def home(path) = path.sub(Dir.home, "~")

      def mark!
        FileUtils.mkdir_p(File.dirname(@mark))
        File.write(@mark, "#{Time.now.utc}\n")
      end
    end
  end
end
