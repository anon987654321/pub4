#!/usr/bin/env ruby
# frozen_string_literal: true

# Batch-send legat applications via mutt with tailored cover letters.
#
# Usage:
#   ruby grok_send_legats.rb --list-batches
#   ruby grok_send_legats.rb --batch bolig_asap --dry-run
#   ruby grok_send_legats.rb --batch innovasjon --confirm
#   ruby grok_send_legats.rb --id 01_innovasjon_norge_master --dry-run
#   ruby grok_send_legats.rb --batch all_sendable --delay 90 --confirm
#
# Env:
#   LEGAT_FROM=bergen@pub.attorney
#   MUTT_CMD=mutt
#   LEGAT_DAILY_CAP=5
#   FORCE_IN=1            # allow Innovasjon Norge sends

require "digest"
require "json"
require "yaml"
require "fileutils"
require "time"
require "date"
require_relative "funding_helpers"

html_lib = File.expand_path("lib/bplan/html.rb", __dir__)
require html_lib if File.exist?(html_lib)

ROOT = File.expand_path(__dir__)
LEGATS_DIR = File.join(ROOT, "legats")
MANIFEST_PATH = File.join(LEGATS_DIR, "manifest.yml")
BATCHES_PATH = File.join(LEGATS_DIR, "batches.yml")
SENT_LOG_PATH = File.join(LEGATS_DIR, "sent_log.yml")
OUTBOX_DIR = File.join(LEGATS_DIR, "outbox")
COVERS_DIR = File.join(ROOT, "covers")
REPORTS_DIR = File.join(LEGATS_DIR, "reports")
FROM = ENV.fetch("LEGAT_FROM", "bergen@pub.attorney")
MUTT = ENV.fetch("MUTT_CMD", "mutt")
DAILY_CAP = ENV.fetch("LEGAT_DAILY_CAP", "5").to_i
FORCE_IN = ENV["FORCE_IN"].to_s == "1"
BCC = ENV["LEGAT_BCC"].to_s.strip
CHROME_CANDIDATES = [
  ENV["CHROME_BIN"],
  "chromium",
  "google-chrome",
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
].compact.uniq.freeze

def load_yaml(path)
  YAML.load_file(path)
end

def html_to_text(path)
  if defined?(Bplan::Html)
    Bplan::Html.to_text(path)
  else
    html = File.read(path)
    html.gsub(/<br\s*\/?>/i, "\n")
        .gsub(%r{</p>}i, "\n\n")
        .gsub(%r{</h[1-6]>}i, "\n\n")
        .gsub(/<li>/i, "• ")
        .gsub(/<[^>]+>/, "")
        .gsub("&nbsp;", " ")
        .gsub("&amp;", "&")
        .gsub(/\n{3,}/, "\n\n")
        .strip
  end
end

def cover_for(app)
  return app["cover_intro"].strip if app["cover_intro"].to_s.strip != ""

  funder = app["funder"]
  custom = File.join(COVERS_DIR, "#{app['id']}.txt")
  return (File.read(custom).strip % { funder: funder }) if File.exist?(custom)

  track = app["track"].to_s
  path = File.join(COVERS_DIR, "#{track}.txt")
  path = File.join(COVERS_DIR, "default.txt") unless File.exist?(path)
  File.read(path).strip % { funder: funder }
end

def chrome_pdf(html_path, pdf_path)
  bin = CHROME_CANDIDATES.find { |c| c.include?("/") ? File.executable?(c) : system("which #{c} >/dev/null 2>&1") }
  return false unless bin

  system(
    bin, "--headless", "--disable-gpu", "--no-sandbox",
    "--print-to-pdf=#{pdf_path}", "file://#{html_path}",
    out: File::NULL, err: File::NULL
  ) && File.exist?(pdf_path)
end

def pdf_path_for(html_path, app_id: nil)
  id = app_id || File.basename(html_path, ".html")
  staged = File.join(LEGATS_DIR, "pdfs", "#{id}.pdf")
  return staged if File.exist?(staged)

  html_path.sub(/\.html\z/, ".pdf")
end

def attachments_for(html_path, app_id: nil)
  pdf = pdf_path_for(html_path, app_id: app_id)
  unless File.exist?(pdf)
    if system("which wkhtmltopdf >/dev/null 2>&1")
      system("wkhtmltopdf", "-q", html_path, pdf, out: File::NULL, err: File::NULL)
    else
      chrome_pdf(File.expand_path(html_path), pdf)
    end
  end
  files = []
  files << pdf if File.exist?(pdf)
  files << html_path if files.empty?
  files
end

def mime_fingerprint(body, attach_paths)
  parts = [body.to_s.encode("UTF-8", invalid: :replace, undef: :replace)]
  attach_paths.each do |path|
    next unless File.exist?(path)

    parts << File.binread(path).force_encoding(Encoding::BINARY)
  end
  Digest::SHA256.hexdigest(parts.map(&:b).join("\0".b))
end

def sent_log
  return { "sent" => {}, "daily" => {} } unless File.exist?(SENT_LOG_PATH)

  log = load_yaml(SENT_LOG_PATH)
  log["sent"] = normalize_sent_entries(log["sent"])
  log["daily"] ||= {}
  log
end

def normalize_sent_entries(raw)
  case raw
  when Hash
    raw
  when Array
    raw.each_with_object({}) do |entry, acc|
      next unless entry.is_a?(Hash) && entry["id"]

      acc[entry["id"]] = {
        "at" => entry["sent_at"] || entry["at"],
        "to" => entry["to"],
        "subject" => entry["subject"],
      }
    end
  else
    {}
  end
end

def today_key
  Date.today.iso8601
end

def daily_sent_count
  sent_log.dig("daily", today_key).to_i
end

def already_sent?(id, app)
  entry = sent_log.dig("sent", id)
  return false unless entry

  if entry["to"] != app["to"] || entry["subject"] != app["subject"]
    warn "warn #{id}: sent_log mismatch (to/subject changed since #{entry['at']})"
    return false
  end

  true
end

def mark_sent(id, to:, subject:, batch: nil, mime_hash: nil, mutt_exit: 0)
  log = sent_log
  log["sent"] ||= {}
  log["daily"] ||= {}
  log["sent"][id] = {
    "at" => Time.now.iso8601,
    "to" => to,
    "subject" => subject,
    "batch" => batch,
    "mime_hash" => mime_hash,
    "mutt_exit" => mutt_exit,
  }.compact
  log["daily"][today_key] = daily_sent_count + 1
  File.write(SENT_LOG_PATH, log.to_yaml)
end

def write_outbox_eml(app, body, attach)
  FileUtils.mkdir_p(OUTBOX_DIR)
  stamp = Time.now.strftime("%Y%m%d_%H%M%S")
  path = File.join(OUTBOX_DIR, "#{stamp}_#{app['id']}.eml")

  eml = <<~EML
    From: #{FROM}
    To: #{app['to']}
    Subject: #{app['subject']}
    Date: #{Time.now.rfc2822}
    MIME-Version: 1.0
    Content-Type: text/plain; charset=UTF-8

    #{body}

    --
    [attachment: #{attach}]
  EML

  File.write(path, eml)
  path
end

def apps_by_id(manifest)
  manifest.fetch("applications", []).to_h { |a| [a["id"], a] }
end

def resolve_batch_ids(batch_name, batch, manifest)
  if batch["auto_from"] == "funding_deadlines"
    funding = FundingHelpers.load_funding(ROOT)
    return funding.fetch("deadlines", []).filter_map do |d|
      next unless d["batch"] == batch_name

      d["legat_id"]
    end.uniq
  end

  if batch["auto"]
    apps = manifest.fetch("applications", [])
    apps = apps.reject { |a| a["draft"] } if batch["exclude_drafts"]
    apps = apps.select { |a| a["sendable"] } if batch["exclude_self"]
    apps = apps.reject { |a| a["low_priority"] } if batch["exclude_low_priority"]
    apps = apps.reject { |a| a["id"].to_s.start_with?("vx_") } if batch["exclude_vx"]
    return apps.map { |a| a["id"] }
  end

  batch.fetch("ids", [])
end

def self_to?(app)
  to = app["to"].to_s.strip.downcase
  from = (app["from"] || FROM).to_s.strip.downcase
  to == from || to == "bergen@pub.attorney"
end

def innovasjon_norge?(id)
  id.to_s.include?("innovasjon_norge")
end

def skip_reason(app, force:)
  id = app["id"]

  return "already sent" if !force && already_sent?(id, app)
  return "draft" if app["draft"] && !force
  return "not sendable" unless app["sendable"] || force
  return "self-to" if self_to?(app) && !force
  return "innovasjon_norge (set FORCE_IN=1)" if innovasjon_norge?(id) && !FORCE_IN && !force
  return "low_priority vx_*" if (app["low_priority"] || id.to_s.start_with?("vx_")) && !force

  nil
end

def send_app(app, dry_run:, force:, confirm:, batch: nil)
  id = app["id"]
  reason = skip_reason(app, force: force)
  if reason
    puts "skip #{id} (#{reason})"
    return :skipped
  end

  if !dry_run && daily_sent_count >= DAILY_CAP
    puts "skip #{id} (daily cap #{DAILY_CAP} reached for #{today_key})"
    return :skipped
  end

  html = File.join(ROOT, app["file"])
  unless File.exist?(html)
    warn "missing #{html} — run: ruby build_legats.rb"
    return :error
  end

  cover = cover_for(app)
  body = "#{cover}\n\n---\n\n#{html_to_text(html)}"
  attach_paths = attachments_for(html, app_id: id)
  fingerprint = mime_fingerprint(body, attach_paths)

  if (prev = sent_log.dig("sent", id)) && prev["mime_hash"] == fingerprint
    puts "skip #{id} (duplicate mime_hash #{fingerprint[0, 12]}…)"
    return :skipped
  end

  puts "→ #{id}"
  puts "  Funder: #{app['funder']}"
  puts "  To: #{app['to']}"
  puts "  Subject: #{app['subject']}"
  puts "  Attach: #{attach_paths.join(', ')}"
  puts "  MIME: #{fingerprint[0, 12]}…"

  if dry_run || !confirm
    eml = write_outbox_eml(app, body, attach_paths.join(", "))
    puts "  [dry-run] wrote #{eml}"
    return :dry_run
  end

  mutt_args = [MUTT, "-e", "set from='#{FROM}'", "-s", app["subject"]]
  mutt_args += ["-b", BCC] if BCC != ""
  attach_paths.each { |path| mutt_args += ["-a", path] }
  mutt_args += ["--", app["to"]]

  IO.popen(mutt_args, "w") do |io|
    io.write(body)
  end

  exit_code = $CHILD_STATUS.exitstatus
  if $CHILD_STATUS.success?
    mark_sent(id, to: app["to"], subject: app["subject"], batch: batch, mime_hash: fingerprint, mutt_exit: exit_code)
    puts "  sent ✓#{BCC != '' ? " (bcc #{BCC})" : ''}"
    :sent
  else
    warn "  mutt failed (exit #{exit_code})"
    :error
  end
end

def write_batch_report(batch_name, ids, results, stats)
  FileUtils.mkdir_p(REPORTS_DIR)
  stamp = Time.now.strftime("%Y%m%d_%H%M%S")
  path = File.join(REPORTS_DIR, "#{stamp}_#{batch_name}.md")

  lines = [
    "# Legat batch report: #{batch_name}",
    "",
    "- **When:** #{Time.now.iso8601}",
    "- **IDs:** #{ids.size}",
    "- **Daily cap:** #{DAILY_CAP} (sent today: #{daily_sent_count})",
    "- **Stats:** #{stats.inspect}",
    "",
    "## Results",
    "",
    "| ID | Status | Detail |",
    "|----|--------|--------|",
  ]

  results.each do |row|
    lines << "| #{row[:id]} | #{row[:status]} | #{row[:detail]} |"
  end

  File.write(path, lines.join("\n") + "\n")
  path
end

# --- CLI ---

dry_run = false
confirm = false
force = false
delay = nil
batch_name = nil
single_id = nil

ARGV.each_with_index do |arg, i|
  case arg
  when "--dry-run" then dry_run = true
  when "--confirm" then confirm = true
  when "--force" then force = true
  when "--list-batches"
    batches = load_yaml(BATCHES_PATH).fetch("batches", {})
    batches.each { |name, b| puts "#{name}: #{b['description']}" }
    exit 0
  when "--list-sendable"
    manifest = load_yaml(MANIFEST_PATH)
    manifest.fetch("applications", []).each do |a|
      next if skip_reason(a, force: false)
      puts "#{a['id']}: #{a['funder']} <#{a['to']}>"
    end
    exit 0
  when "--batch" then batch_name = ARGV[i + 1]
  when "--id" then single_id = ARGV[i + 1]
  when "--delay" then delay = ARGV[i + 1].to_i
  end
end

unless File.exist?(MANIFEST_PATH)
  warn "Run: ruby build_legats.rb"
  exit 1
end

manifest = load_yaml(MANIFEST_PATH)
index = apps_by_id(manifest)

ids =
  if single_id
    [single_id]
  elsif batch_name
    batches = load_yaml(BATCHES_PATH).fetch("batches", {})
    batch = batches[batch_name] or abort "unknown batch: #{batch_name}"
    delay ||= batch["delay_seconds"]
    resolve_batch_ids(batch_name, batch, manifest)
  else
    abort "Usage: ruby grok_send_legats.rb --batch NAME [--dry-run|--confirm] | --id ID"
  end

delay ||= 60
stats = { sent: 0, skipped: 0, error: 0, dry_run: 0 }
results = []

ids.each_with_index do |id, i|
  app = index[id] or (warn "unknown id: #{id}"; stats[:error] += 1; results << { id: id, status: "error", detail: "unknown id" }; next)
  status = send_app(app, dry_run: dry_run, force: force, confirm: confirm, batch: batch_name)
  results << { id: id, status: status.to_s, detail: app["funder"] }
  case status
  when :sent then stats[:sent] += 1
  when :skipped then stats[:skipped] += 1
  when :error then stats[:error] += 1
  when :dry_run then stats[:dry_run] += 1
  end
  sleep delay if i < ids.length - 1 && !dry_run && confirm
end

report = write_batch_report(batch_name || single_id || "run", ids, results, stats) if batch_name || single_id

puts "\nDone: #{stats.inspect}"
puts "Log: #{SENT_LOG_PATH}" if File.exist?(SENT_LOG_PATH)
puts "Report: #{report}" if report