#!/usr/bin/env ruby
# frozen_string_literal: true

require "shellwords"

app = ARGV.fetch(0) { abort "usage: solid_queue_proof.rb APP" }
app_dir = "/home/#{app}/app"
abort "missing #{app_dir}" unless File.directory?(app_dir)

%W[/etc/#{app}.env /etc/rails/#{app}.env].each do |path|
  next unless File.readable?(path)

  File.foreach(path) do |line|
    key, value = line.strip.split("=", 2)
    next if key.nil? || key.start_with?("#") || value.nil?

    ENV[key] = value
  end
end

secret = ENV["SECRET_KEY_BASE"]
abort "missing SECRET_KEY_BASE in /etc/#{app}.env" if secret.to_s.empty?

runner = <<~RUBY
  n = 0
  30.times do
    n = SolidQueue::Process.count
    break if n.positive?

    sleep 2
  end
  warn "solid_queue: #{app} processes=\#{n}"
  exit(n.positive? ? 0 : 1)
RUBY

cmd = [
  "su", "-m", app, "-c",
  [
    "export HOME=/home/#{app}",
    "export RAILS_ENV=production",
    "export SOLID_QUEUE_IN_PUMA=true",
    "export SECRET_KEY_BASE=#{Shellwords.escape(secret)}",
    "cd #{Shellwords.escape(app_dir)}",
    "bundle34 exec rails runner -e production #{Shellwords.escape(runner)}"
  ].join(" && ")
]

success = system(*cmd)
exit(success ? 0 : 1)