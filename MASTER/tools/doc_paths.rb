# frozen_string_literal: true

require "open3"

# Every path a document names must exist on disk.
#
# The DEPLOY/ tree became RAILS/ and four documents kept pointing at the dead
# path, including the root CLAUDE.md, which was deleted for that drift. A
# document that names a file nobody can open is worse than no document: it reads
# as current and sends the reader somewhere empty.
#
#   ruby MASTER/tools/doc_paths.rb           # report
#   ruby MASTER/tools/doc_paths.rb --json    # machine-readable
#
# Enforced by MASTER/test/test_doc_paths.rb against a committed baseline, so it
# lands green and ratchets down.

require "json"

module Pub4
  class DocPaths
    ROOT = File.expand_path("../..", __dir__)
    TREES = %w[MASTER RAILS OPENBSD].freeze
    SKIP = %r{/(node_modules|vendor|knowledge|output|tmp|\.master|public/assets|\.git)/}

    # Backticked tokens carrying a slash. Everything else in prose is a word.
    TOKEN = /`([A-Za-z0-9_.@\-\/]*\/[A-Za-z0-9_.@\-\/]+)`/

    # Roots a relative mention resolves against, tried in order. A doc inside
    # RAILS/shared/ writing `shared/config/routes/social.rb` means RAILS/shared,
    # and writing `config/routes/social.rb` means the same file.
    def self.roots_for(doc)
      dir = File.dirname(doc)
      roots = [ROOT, dir]
      parts = doc.split("/")
      roots << File.join(ROOT, parts[0]) if parts.size > 1              # MASTER, RAILS, OPENBSD
      roots << File.join(ROOT, parts[0], parts[1]) if parts.size > 2    # RAILS/shared, RAILS/brgen
      # MASTER/DEBT.md writes "voice/engines.rb" for MASTER/lib/voice/engines.rb.
      roots << File.join(ROOT, parts[0], "lib") if parts.size > 1
      # Rails view/partial mentions ("home/index", "comments/form") resolve under app/views.
      roots << File.join(dir, "app/views") << File.join(ROOT, parts[0], parts[1].to_s, "app/views")
      roots.uniq
    end

    # Documents legitimately write "bin/ci" for a file each of three apps has its
    # own copy of. A token that is the tail of some real tracked path resolves.
    def self.tracked
      @tracked ||= begin
        out, _status = Open3.capture2("git", "ls-files", chdir: ROOT)
        out.split("\n")
      end
    end

    def self.tracked_suffix?(candidate)
      @suffixes ||= tracked.group_by { |path| File.basename(path) }
      return true if (@suffixes[File.basename(candidate)] || []).any? { |path| path.end_with?(candidate) }

      # "app/views" and "public/assets/" name directories, which git ls-files
      # never lists on their own.
      @dirs ||= tracked.flat_map { |path| dir = File.dirname(path); dir.split("/").each_with_object([]) { |part, acc| acc << (acc.last ? "#{acc.last}/#{part}" : part) } }.uniq
      return true if @dirs.any? { |dir| dir == candidate || dir.end_with?("/#{candidate}") }

      # public/assets exists on disk and is gitignored, so git ls-files cannot
      # see it. Walk once and cache -- a ** glob per unresolved token took the
      # test past two minutes.
      untracked_dirs.include?(candidate) || untracked_dirs.any? { |dir| dir.end_with?("/#{candidate}") }
    end

    PRUNE = %w[.git node_modules tmp log .master knowledge output storage].freeze

    def self.untracked_dirs
      @untracked_dirs ||= TREES.flat_map do |tree|
        found = []
        stack = [File.join(ROOT, tree)]
        while (dir = stack.pop)
          children = begin
            Dir.children(dir)
          rescue SystemCallError
            []
          end

          children.each do |child|
            next if PRUNE.include?(child)

            path = File.join(dir, child)
            next unless File.directory?(path) && !File.symlink?(path)

            found << path.sub("#{ROOT}/", "")
            stack << path
          end
        end
        found
      end
    end

    # A token is path-shaped when it carries an extension, ends in a slash, or
    # starts at a directory this repo actually has. "pending/accepted/blocked"
    # is a status list and matches none of those.
    KNOWN_HEADS = %w[
      MASTER RAILS OPENBSD STUDIO bin lib core data app config test spec web
      gates shared tools script db public frontend engines dotfiles etc
    ].freeze

    def self.path_shaped?(token)
      return false if token.start_with?("http", "/")          # urls and routes
      return false if token.start_with?("@")                  # npm specifiers: @rails/request.js
      return false if token.include?("*") || token.include?("..")
      return true if token.end_with?("/")
      return true if File.extname(token).match?(/\A\.[a-z0-9]{1,6}\z/i)

      KNOWN_HEADS.include?(token.split("/").first)
    end

    # A line recording that something was deleted is doing its job by naming a
    # path that no longer exists. DEBT.md, SEVERANCE.md and restoration notes are
    # built out of such lines; failing them would delete the record a second time.
    # Also covers assertions of absence -- "no config/master.key in git",
    # "stimulus_components.js must not return" -- where the path existing is the
    # bug the sentence exists to prevent.
    HISTORICAL = /\b(deleted|removed|retired|no longer|used to|was renamed|gone|absent|recovered from|missing|
                     must not|never|without|forbidden|deprecated|do not commit|no )\b|\b[0-9a-f]{7,40}\b/xi

    def self.historical?(line)
      line.match?(HISTORICAL)
    end

    # "shared/empty_state" is render("shared/empty_state") -> shared/_empty_state.html.erb
    def self.partial?(candidate, doc)
      base = File.basename(candidate)
      return false unless File.extname(base).empty?

      # Both spellings appear: "shared/empty_state" (render argument) and
      # "shared/_icon" (the partial file, extension omitted).
      partial = File.join(File.dirname(candidate), base.start_with?("_") ? base : "_#{base}")
      roots_for(doc).any? do |root|
        Dir[File.join(root, "#{partial}.*")].any?
      end || tracked.any? { |path| path.include?("/#{partial}.") }
    end

    def self.docs
      TREES.flat_map { |tree| Dir[File.join(ROOT, tree, "**", "*.md")] }
           .reject { |f| f =~ SKIP }
           .map { |f| f.sub("#{ROOT}/", "") }
           .sort
    end

    # Directories a Rails app creates when it runs, not when it is cloned.
    # `untracked_dirs` finds them by walking the disk, which works on a machine
    # that has booted the app and on the deploy host, and fails everywhere else:
    # in a fresh clone or a new `MASTER/bin/pub4 worktree` they have never been created,
    # so START_HERE's `web/storage/` and `web/log/` and DEBT.md's `public/assets`
    # were reported as documents pointing at nothing.
    #
    # That is a check whose verdict depends on which checkout it runs in, which
    # is the same defect RAILS/gates/lib/source/generated_asset.rb carries a paragraph
    # about for mtimes. A path is here because Rails will make it, and a
    # reference to it is correct whether or not this machine has run the app.
    RUNTIME_LEAVES = %w[assets log storage tmp cache pids sockets].freeze

    def self.runtime_dir?(candidate)
      leaf = File.basename(candidate)
      return false unless RUNTIME_LEAVES.include?(leaf)

      parent = File.dirname(candidate)
      return true if parent == "."

      # The parent has to be real, so `nonsense/log` stays dead.
      TREES.any? { |tree| File.directory?(File.join(ROOT, tree, parent)) } ||
        File.directory?(File.join(ROOT, parent)) ||
        tracked_suffix?(parent)
    end

    def self.resolve(token, doc)
      candidate = token.chomp("/")
      return true if roots_for(doc).any? { |root| File.exist?(File.join(root, candidate)) }
      return true if tracked_suffix?(candidate)
      return true if runtime_dir?(candidate)

      loose_match?(candidate)
    end

    # Documents abbreviate: FINAL_TODO.md writes `shared/_shell.scss` for
    # RAILS/shared/app/assets/stylesheets/_shell.scss. Accept when a real file
    # carries that basename and every directory the token names appears in its
    # path -- enough to prove the reader can find it, strict enough that
    # `db/structure.sql` (no such basename anywhere) stays dead.
    def self.loose_match?(candidate)
      base = File.basename(candidate)
      dirs = File.dirname(candidate).split("/").reject { |part| part == "." }
      @suffixes ||= tracked.group_by { |path| File.basename(path) }

      candidates = @suffixes[base] || []
      candidates += (@suffixes.keys.grep(/\A#{Regexp.escape(base)}\./).flat_map { |key| @suffixes[key] }) if File.extname(base).empty?
      candidates.any? { |path| dirs.all? { |dir| path.split("/").include?(dir) } }
    end

    def self.run
      findings = Hash.new { |hash, key| hash[key] = [] }
      checked = 0

      docs.each do |doc|
        body = File.read(File.join(ROOT, doc))
        # ENGINES.md is a recipe whose paths carry a placeholder vertical name.
        next if body.include?("<!-- doc_paths: ignore -->")

        # Paragraphs, not lines: these documents hard-wrap, so the path and the
        # SHA that explains its absence routinely land on different lines.
        paragraphs = body.split(/\n{2,}/)

        body.scan(TOKEN).flatten.uniq.each do |token|
          next unless path_shaped?(token)

          checked += 1
          next if resolve(token, doc)
          next if partial?(token.chomp("/"), doc)
          next if paragraphs.select { |para| para.include?("`#{token}`") }.all? { |para| historical?(para) }

          findings[doc] << token
        end
      end

      { checked:, findings: findings.sort.to_h }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  report = Pub4::DocPaths.run
  dead = report[:findings].values.sum(&:size)

  if ARGV.include?("--json")
    puts JSON.pretty_generate(report)
  else
    report[:findings].each do |doc, tokens|
      puts "#{doc}"
      tokens.each { |token| puts "  #{token}" }
    end
    puts
    puts "#{report[:checked]} paths checked, #{dead} dead across #{report[:findings].size} documents"
  end

  exit(dead.zero? ? 0 : 1)
end
