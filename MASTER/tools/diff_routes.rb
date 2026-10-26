# frozen_string_literal: true

# The diff→check router: I am about to edit these paths — which owner rows
# govern them, and which check does each owner declare?
#
# The data already exists; this tool only reads it. PATH_OWNERSHIP.yml carries
# one row per owned path with the check that fails when the row's claim stops
# being true, and checks/checks.yml routes execution. A second path→check
# table here would be exactly the kind of hand-maintained neighbour checks.yml
# was written to retire, so there is none: the router resolves a path against
# PATH_OWNERSHIP and prints what those rows promise. For the whole ladder use
# `MASTER/bin/operator check`; for the smallest proof, the printed check.
#
#   ruby MASTER/tools/diff_routes.rb MASTER/law/css.rb RAILS/master/public/face.css
#   ruby MASTER/tools/diff_routes.rb --diff            # working tree vs HEAD
#   ruby MASTER/tools/diff_routes.rb --diff HEAD~1     # one commit back
#   git diff --name-only origin/main | ruby MASTER/tools/diff_routes.rb --stdin
#
# A path no row claims is printed as a gap and the exit is 1 — the same
# honesty coverage_reconciliation uses: a router that shrugs at an unowned
# path is a router that routes nothing. Add the row, or name why the path is
# out of scope. Not registered as a check on purpose: it has zero real runs
# and is a hypothesis, not an instrument.

require "open3"
require "yaml"

module Deploy
  class DiffRoutes
    OWNERSHIP = File.expand_path("../PATH_OWNERSHIP.yml", __dir__)
    REPO_ROOT = File.expand_path("../..", __dir__)
    MASTER_NAME = "MASTER"

    attr_reader :gaps

    def self.run(paths:, ownership_path: OWNERSHIP, repo_root: REPO_ROOT, io: $stdout)
      new(ownership_path:, repo_root:, io:).run(paths)
    end

    def initialize(ownership_path: OWNERSHIP, repo_root: REPO_ROOT, io: $stdout)
      @ownership_path = ownership_path
      @repo_root = File.expand_path(repo_root)
      @io = io
      @gaps = []
    end

    def run(paths)
      rows = load_ownership
      paths.each { |path| route(path, rows) }
      @gaps
    end

    private

    def load_ownership
      YAML.safe_load_file(@ownership_path).fetch("ownership")
    rescue StandardError => e
      raise "ownership unreadable: #{@ownership_path} (#{e.class}: #{e.message})"
    end

    def route(path, rows)
      candidates = coordinates(path)
      matches = rows.filter_map do |key, row|
        next unless owned?(candidates, key)

        [key, row.is_a?(Hash) ? row : {}]
      end.sort_by { |key, _| -key.length }

      if matches.empty?
        @gaps << path
        @io.puts "#{path}\n  GAP — no PATH_OWNERSHIP row claims this path; add one or name why it is out of scope"
        return
      end

      @io.puts path.to_s
      matches.each_with_index do |(key, row), index|
        lead = index.zero? ? "owner " : "also  "
        @io.puts "  #{lead}#{key} (#{row['risk'] || 'risk undeclared'})"
        @io.puts "  check  #{row['check'] || '(no check named — the row promises nothing testable)'}"
        @io.puts "  why    #{row['purpose'].to_s.tr("\n", ' ')}" if index.zero? && row["purpose"]
      end
    end

    # A diff prints repo-root paths (MASTER/law/css.rb); ownership rows are
    # written in MASTER-relative coordinates, with ../ for sibling trees and
    # RAILS/master/ for the one RAILS subtree MASTER owns directly. A path is
    # tried in every coordinate it could plausibly be claimed under, most
    # literal first.
    def coordinates(path)
      path = path.to_s.sub(%r{\A\./}, "")
      candidates = [path]
      candidates << path.delete_prefix("#{MASTER_NAME}/") if path.start_with?("#{MASTER_NAME}/")
      %w[RAILS OPENBSD STUDIO].each do |tree|
        candidates << "../#{path}" if path.start_with?("#{tree}/")
      end
      candidates.compact.uniq
    end

    def owned?(candidates, key)
      candidates.any? do |candidate|
        candidate == key ||
          (key.end_with?("/") && candidate.start_with?(key)) ||
          File.fnmatch(key, candidate, File::FNM_PATHNAME)
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  base = nil
  stdin = false
  args = ARGV.dup
  args.reject! do |arg|
    case arg
    when "--diff"       then true
    when /\A--diff=/    then base = arg.delete_prefix("--diff=")
    when "--stdin"      then stdin = true
    else false
    end
  end
  base = "HEAD" if ARGV.include?("--diff") && base.nil?

  paths =
    if stdin
      $stdin.each_line.map(&:strip).reject(&:empty?)
    elsif base
      out, status = Open3.capture2e("git", "-C", Deploy::DiffRoutes::REPO_ROOT, "diff", "--name-only", base)
      abort "diff_routes: git diff failed (#{out})" unless status.success?

      out.lines.map(&:strip).reject(&:empty?)
    else
      args
    end

  if paths.empty?
    abort "usage: diff_routes.rb <path...> | --diff [<base>] | --stdin  — routes paths to their PATH_OWNERSHIP rows"
  end

  gaps = Deploy::DiffRoutes.run(paths:)
  puts "diff_routes: #{paths.size} path(s), #{gaps.size} unowned"
  exit 1 unless gaps.empty?
end
