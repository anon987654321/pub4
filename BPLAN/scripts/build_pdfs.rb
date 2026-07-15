#!/usr/bin/env ruby
# frozen_string_literal: true

# Build PDF attachments for sendable legat letters.
# Usage: ruby scripts/build_pdfs.rb [--all|--id ID] [--force]
require "fileutils"
require "yaml"

ROOT = File.expand_path("..", __dir__)
LEGATS = File.join(ROOT, "legats")
PDF_DIR = File.join(LEGATS, "pdfs")
MANIFEST = File.join(LEGATS, "manifest.yml")
def chrome_bins
  explicit = ENV["CHROME_BIN"].to_s.strip
  candidates = [
    explicit,
    "chromium",
    "google-chrome",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ].compact.uniq
  candidates.select { |bin| bin.include?("/") ? File.executable?(bin) : system("which #{bin} >/dev/null 2>&1") }
end

def chrome_pdf(html_path, pdf_path)
  bin = chrome_bins.first
  return false unless bin

  system(
    bin, "--headless", "--disable-gpu", "--no-sandbox",
    "--print-to-pdf=#{pdf_path}", "file://#{File.expand_path(html_path)}",
    out: File::NULL, err: File::NULL
  ) && File.exist?(pdf_path)
end

def html_to_pdf(html_path, pdf_path, force:)
  return pdf_path if File.exist?(pdf_path) && !force

  FileUtils.mkdir_p(File.dirname(pdf_path))
  if system("which wkhtmltopdf >/dev/null 2>&1")
    ok = system("wkhtmltopdf", "-q", html_path, pdf_path, out: File::NULL, err: File::NULL)
    return pdf_path if ok && File.exist?(pdf_path)
  end
  return pdf_path if chrome_pdf(html_path, pdf_path)

  warn "fail: #{html_path} (install wkhtmltopdf or set CHROME_BIN=chromium)"
  nil
end

only_id = nil
all_apps = false
force = false
ARGV.each_with_index do |arg, i|
  case arg
  when "--all" then all_apps = true
  when "--force" then force = true
  when "--id" then only_id = ARGV[i + 1]
  end
end

manifest = YAML.load_file(MANIFEST)
apps = manifest.fetch("applications", [])
apps = apps.select { |a| a["id"] == only_id } if only_id
apps = apps.select { |a| a["sendable"] } if all_apps || only_id.nil?

built = 0
skipped = 0
failed = 0

apps.each do |app|
  id = app["id"]
  html = File.join(ROOT, app["file"])
  pdf = File.join(PDF_DIR, "#{id}.pdf")

  unless File.exist?(html)
    warn "missing html: #{html}"
    failed += 1
    next
  end

  if File.exist?(pdf) && !force && File.mtime(pdf) >= File.mtime(html)
    skipped += 1
    next
  end

  if html_to_pdf(html, pdf, force: force)
    puts "pdf #{id}"
    built += 1
  else
    failed += 1
  end
end

puts "done: built=#{built} skipped=#{skipped} failed=#{failed} dir=#{PDF_DIR}"
exit 1 if failed.positive?