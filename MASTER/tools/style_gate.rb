#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require_relative "../lib/operator/ruby_runner"
require_relative "../lib/trace/dmesg"

ROOT = File.expand_path("..", __dir__)
REPO = File.expand_path("../..", ROOT)
RAILS_ROOT = File.join(REPO, "RAILS")
RUBY = Operator::RubyRunner.ruby_cmd
BUNDLE = Operator::RubyRunner.bundle_cmd

def run(label, command, chdir: ROOT)
  out, err, status = Open3.capture3(*command, chdir:)
  body = [out, err].map(&:strip).reject(&:empty?).join("\n")
  { label:, ok: status.success?, body:, exit: status.exitstatus }
end

def bundle_exec_rubocop(shared_rubocop, _app_dir)
  [BUNDLE, "exec", RUBY, shared_rubocop]
end

results = []
results << run(
  "MASTER rubocop (lib test script bin)",
  [BUNDLE, "exec", RUBY, "-S", "rubocop", "--format", "simple", "lib", "test", "script", "bin"],
  chdir: ROOT,
)

shared_rubocop = File.join(RAILS_ROOT, "__shared", "bin", "rubocop")
if File.executable?(shared_rubocop)
  Dir.glob(File.join(RAILS_ROOT, "*")).select { |path| File.directory?(path) }.sort.each do |app|
    gemfile = File.join(app, "Gemfile")
    next unless File.file?(gemfile)

    command = bundle_exec_rubocop(shared_rubocop, app) + ["--format", "simple"]
    results << run(
      "OPERATOR #{File.basename(app)} rubocop",
      command,
      chdir: app,
    )
  end
end

eslint = File.join(ROOT, "web", "eslint.config.mjs")
if File.file?(eslint)
  results << run(
    "MASTER web eslint",
    %w[npx --yes eslint@9 web/public --max-warnings 0],
    chdir: ROOT,
  )
end

failed = results.reject { |row| row[:ok] }
results.each_with_index do |row, index|
  unit = "style#{index}"
  Master::Trace::Dmesg.attach(unit, "style0", row[:label])
  Master::Trace::Dmesg::Report.print(unit, row[:body], parent: "style0") unless row[:body].empty?
  Master::Trace::Dmesg.status(unit, row[:ok] ? "clean" : "failed")
end

if failed.any?
  Master::Trace::Dmesg.status("style0", "#{failed.size} check(s) failed")
  exit 1
end

Master::Trace::Dmesg.status("style0", "passed")
exit 0
