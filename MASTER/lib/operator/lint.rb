# frozen_string_literal: true

require "fix/change_scope"
require "fix/method_debt"
require "fix/scan/source_override"

module Operator

  # The checkout's git, quiet on stderr: a path git does not hold is an answer here.
  LintRepo = Data.define(:root) do
    def git(*args) = Master::Io::Exec.capture2("git", "-C", root, *args, err: File::NULL)

    def relative(path) = File.expand_path(path).delete_prefix("#{root}/")

    # The text at +revision+ ("" for the index), or nil where git holds none.
    def blob(revision, path)
      out, status = git("show", "#{revision}:#{relative(path)}")
      status.success? ? out : nil
    end
  end

  # `bin/operator lint`: the house rules over the files a change touched. Paths
  # given are scanned as named; with none, the files the diff names are.
  # --staged judges what the commit will hold, and --changed-lines only what
  # the diff changed; each is explained where it is read below.
  class Lint
    FILE_SIZE_LAWS = %w[SMALL_FILES JS_MODULE_SIZE].freeze
    BASE = "HEAD"

    # +root+ is the git checkout; +scanner+ answers scan(path, depth:).
    def initialize(root:, scanner:, staged: false, changed_only: false)
      @repo = LintRepo.new(root:)
      @scanner = scanner
      @staged = staged
      @changed_only = changed_only
      @diff_base = staged ? "--cached" : BASE
    end

    # Absolute paths of the files to judge: +paths+ as named, directories walked,
    # or with none, every file the diff names that the scan can read.
    def targets(paths = [])
      return named(paths) unless paths.empty?

      out, = @repo.git("diff", "--name-only", "--diff-filter=d", @diff_base)
      out.lines.map { |line| File.join(@repo.root, line.chomp) }.select { |path| @staged || File.file?(path) }
    end

    # [[path, finding], ...] for +files+, each finding kept as the mode says.
    def findings(files)
      files.flat_map do |path|
        source = staged_source(path)
        rows = scan(path, source)
        rows = in_diff(path, rows, source:) if @changed_only
        rows.map { |finding| [path, finding] }
      end
    end

    private

    def named(paths)
      expanded = paths.flat_map do |target|
        target = File.expand_path(target)
        File.directory?(target) ? Dir.glob(File.join(target, "**/*")) : [target]
      end
      expanded.select { |path| File.file?(path) || (@staged && staged_source(path)) }
    end

    # With --staged the text judged is the staged blob, never the working-tree
    # file, because the line ranges come from the index's diff: in a shared
    # checkout another session's unstaged edits to the same file shifted every
    # line and leaked its findings into this commit. The blob is scanned under
    # the real path (Fix::Scan::SourceOverride), so path guards still apply.
    def staged_source(path)
      return unless @staged

      @staged_sources ||= {}
      @staged_sources.fetch(path) { @staged_sources[path] = @repo.blob("", path) }
    end

    def scan(path, source)
      result = if source
                 Master::Fix::Scan::SourceOverride.with(path => source) { @scanner.scan(path, depth: :deep) }
               else
                 @scanner.scan(path, depth: :deep)
               end
      result.ok? ? Array(result.value!) : []
    end

    # --changed-lines keeps what the diff changed, read through Fix::ChangeScope as
    # /fix's own per-fix checks read it. A file-size finding counts when the diff
    # made the file longer; a finding on a `def` line counts when the diff touches
    # that method and the method is worse than at HEAD (Fix::MethodDebt); any other
    # finding counts when its line is one the diff changed.
    def in_diff(path, rows, source:)
      scope = scope_of(path, source)
      text = source || File.read(path, encoding: "UTF-8")

      methods = methods_of(path, text)
      rows.select do |finding|
        method = methods[finding[:line].to_i]
        next scope.grew? if FILE_SIZE_LAWS.include?(finding[:law].to_s)
        next scope.covers?(finding) unless method

        scope.touches?(method.range) && method_debt(path, text).worse?(finding)
      end
    end

    def methods_of(path, text)
      Master.language_for(path) == "ruby" ? Master::Fix::MethodDebt.methods_by_line(text) : {}
    end

    # HEAD's findings, scanned under the same path, for the comparison MethodDebt
    # makes, once a file. A file new since HEAD has none.
    def method_debt(path, text)
      @debts ||= {}

      @debts[path] ||= begin
        base_source = @repo.blob(BASE, path).to_s
        base_findings = base_source.empty? ? [] : scan(path, base_source)
        Master::Fix::MethodDebt.new(source: text, base_source:, base_findings:)
      end
    end

    # A path the diff does not name is unchanged, unless git does not hold it at
    # the base: then every line of it is new.
    def scope_of(path, source)
      @scopes ||= Master::Fix::ChangeScope.from_diff(@repo.git("diff", "-U0", @diff_base).first)

      @scopes.fetch(@repo.relative(path)) do
        held = !@repo.blob(@staged ? "" : BASE, path).nil?
        Master::Fix::ChangeScope.between("", held ? "" : (source || File.read(path)))
      end
    end
  end
end
