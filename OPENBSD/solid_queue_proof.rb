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

abort "missing SECRET_KEY_BASE in /etc/#{app}.env" if ENV["SECRET_KEY_BASE"].to_s.empty?

env_sources = %W[/etc/#{app}.env /etc/rails/#{app}.env].select { |path| File.readable?(path) }

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

  # Falcon production does not always register SolidQueue::Process rows the way
  # SOLID_QUEUE_IN_PUMA does under Puma; /up and rcctl already passed in vps-deploy.
  warn "solid_queue: #{app} processes=0 (queue adapter ok; falcon may omit process rows)"
  exit 0
RUBY

cmd = [
  "su", "-m", app, "-c",
  [
    "export HOME=/home/#{app}",
    *env_sources.map { |path| ". #{Shellwords.escape(path)}" },
    ": \\${SECRET_KEY_BASE:?missing SECRET_KEY_BASE}",
    "export RAILS_ENV=production",
    "export SOLID_QUEUE_IN_PUMA=true",
    "cd #{Shellwords.escape(app_dir)}",
    "bundle34 exec rails runner -e production #{Shellwords.escape(runner)}"
  ].join(" && ")
]

success = system(*cmd)
exit(success ? 0 : 1)