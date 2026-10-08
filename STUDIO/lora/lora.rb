#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"

ROOT = File.expand_path(__dir__)
SUBJECTS = Dir.children(ROOT).sort.filter_map do |name|
  next unless File.file?(File.join(ROOT, name, "lora"))
  name
end.freeze

options = { subject: ENV["SUBJECT"].to_s }

parser = OptionParser.new do |opts|
  opts.banner = "Usage: lora.rb [--subject NAME] [--list] [lane options]"
  opts.on("--subject NAME", SUBJECTS, "subject wrapper to invoke") { |name| options[:subject] = name }
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

parser.order!(ARGV)
subject = options[:subject].strip
subject = ARGV.shift if subject.empty? && ARGV.first && !ARGV.first.start_with?("-")

abort "lora: choose --subject NAME (have: #{SUBJECTS.join(", ")})" if subject.empty?
abort "lora: unknown subject #{subject.inspect} (have: #{SUBJECTS.join(", ")})" unless SUBJECTS.include?(subject)

exec(File.join(ROOT, subject, "lora"), *ARGV)
