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

secret = ENV.fetch("SECRET_KEY_BASE")
abort "missing SECRET_KEY_BASE in /etc/#{app}.env" if secret.to_s.empty?

runner = <<~RUBY
  adapter = ActiveJob::Base.queue_adapter
  unless adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
    warn "solid_queue: #{app} adapter=\#{adapter.class.name}"
    exit 1
  end

  n = 0
  15.times do
    n = SolidQueue::Process.count
    break if n.positive?

    sleep 2
  end

  if n.positive?
    warn "solid_queue: #{app} processes=\#{n}"
    exit 0
  end

  warn "solid_queue: #{app} processes=0 — adapter present, no worker registered"
  exit 1
RUBY

cmd = [
  "su", "-m", app, "-c",
  [
    "export HOME=/home/#{app}",
    "cd #{Shellwords.escape(app_dir)}",
    "env RAILS_ENV=production SOLID_QUEUE_IN_PUMA=true SECRET_KEY_BASE=#{Shellwords.escape(secret)} bundle34 exec rails runner -e production #{Shellwords.escape(runner)}",
  ].join(" && "),
]

success = system(*cmd)
exit(success ? 0 : 1)
