#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "_toolkit/preflight"

ROOT = File.expand_path(__dir__)
SUBJECTS = Dir.children(ROOT).sort.filter_map do |name|
  next unless File.file?(File.join(ROOT, name, "lora"))
  name
end.freeze

# One line of fact per subject, from files alone: no network, no credentials.
def subject_status(name)
  dir = File.join(ROOT, name)
  trigger = File.read(File.join(dir, "subject.env"))[/^TRIGGER=(\S+)/, 1].to_s
  dataset = File.join(dir, "dataset")
  report = File.directory?(dataset) ? Preflight.dataset_report(dataset, trigger:) : nil
  sidecar = File.join(dir, "weights", File.read(File.join(dir, "subject.env"))[/^MODEL=(\S+)/, 1].to_s, "replicate_training.json")
  version = File.file?(sidecar) ? JSON.parse(File.read(sidecar))["version"] : nil
  weights = Dir[File.join(dir, "weights", "**", "*.safetensors")].length
  spent = Preflight.ledger_seconds(File.join(dir, "out", "ledger.jsonl"), "render") +
          Preflight.ledger_seconds(File.join(dir, "out", "ledger.jsonl"), "train")
  next_step = if report.nil? || report.images.empty? then "no dataset: curate photos into sources/, then dataset/"
              elsif !report.ok? then "dataset: #{report.problems.first}"
              elsif version.nil? then "ready to train: ./lora --subject #{name} --train-replicate --dry-run"
              else "trained; render: ./lora --subject #{name} --generate-replicate --draft"
              end
  format("%-9s images=%-3s trained=%-5s weights=%-2s billed=%ds\n          next: %s", name, report&.images&.length || 0,
         version ? "yes" : "no", weights, spent, next_step)
end

options = { subject: ENV["SUBJECT"].to_s }

parser = OptionParser.new do |opts|
  opts.banner = "Usage: lora.rb [--subject NAME] [--list] [lane options]"
  opts.on("--subject NAME", SUBJECTS, "subject wrapper to invoke") { |name| options[:subject] = name }
  opts.on("--status", "per subject: dataset, trained version, weights, spend, and what blocks the next step") do
    SUBJECTS.each { |name| puts subject_status(name) }
    exit 0
  end
  opts.on("--list", "list available subjects") do
    puts SUBJECTS.join("\n")
    exit 0
  end
  opts.on("-h", "--help", "show subject routing help") do
    puts opts
    puts "subjects: #{SUBJECTS.join(", ")}"
    exit 0
  end
end

# The router owns the leading options only. The first argument it does not own,
# and everything after it, belongs to the subject's lane: OptionParser would
# reject --generate-replicate as invalid before the lane ever saw it.
head = []
while %w[--subject --list --status -h --help].include?(ARGV.first.to_s.split("=").first)
  flag = ARGV.shift
  head << flag
  head << ARGV.shift if flag == "--subject"
end
parser.order!(head)
subject = options[:subject].strip
subject = ARGV.shift if subject.empty? && ARGV.first && !ARGV.first.start_with?("-")

abort "lora: choose --subject NAME (have: #{SUBJECTS.join(", ")})" if subject.empty?
abort "lora: unknown subject #{subject.inspect} (have: #{SUBJECTS.join(", ")})" unless SUBJECTS.include?(subject)

exec(File.join(ROOT, subject, "lora"), *ARGV)
