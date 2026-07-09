#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

ROOT = File.expand_path("..", __dir__)
REPO = File.expand_path("../..", ROOT)
DEPLOY_RAILS = File.join(REPO, "DEPLOY", "rails")

def run(label, command, chdir: ROOT)
  out, err, status = Open3.capture3(*command, chdir: chdir)
  body = [out, err].map(&:strip).reject(&:empty?).join("\n")
  { label: label, ok: status.success?, body: body, exit: status.exitstatus }
end

def bundle_exec_rubocop(shared_rubocop, app_dir)
  if system("which ruby34 >/dev/null 2>&1")
    %w[ruby34 bundle exec] + [shared_rubocop]
  else
    ["bundle", "exec", shared_rubocop]
  end
end

results = []
results << run(
  "MASTER rubocop (lib test script bin)",
  %w[bundle exec rubocop --format simple lib test script bin],
  chdir: ROOT
)

shared_rubocop = File.join(DEPLOY_RAILS, "shared", "bin", "rubocop")
if File.executable?(shared_rubocop)
  Dir.glob(File.join(DEPLOY_RAILS, "*")).select { |path| File.directory?(path) }.sort.each do |app|
    gemfile = File.join(app, "Gemfile")
    next unless File.file?(gemfile)

    command = bundle_exec_rubocop(shared_rubocop, app) + ["--format", "simple"]
    results << run(
      "DEPLOY #{File.basename(app)} rubocop",
      command,
      chdir: app
    )
  end
end

eslint = File.join(ROOT, "web", "eslint.config.mjs")
if File.file?(eslint)
  results << run(
    "MASTER web eslint",
    %w[npx --yes eslint@9 web/public --max-warnings 0],
    chdir: ROOT
  )
end

failed = results.reject { |row| row[:ok] }
results.each do |row|
  tag = row[:ok] ? "ok:" : "warn:"
  puts "#{tag} #{row[:label]}"
  puts row[:body] unless row[:body].empty?
end

if failed.any?
  warn "warn: style_gate #{failed.size} check(s) failed"
  exit 1
end

puts "ok: style_gate passed"
exit 0