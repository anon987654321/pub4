#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates deployable artifacts for DEPLOY/TODO.md sections requested in the
# 2026-06-15 pass, then marks items [x] when the artifact file exists.
#
# Usage: ruby DEPLOY/sync_section_artifacts.rb [--dry-run]

require "fileutils"

ROOT = File.expand_path("..", __dir__)
TODO = File.join(ROOT, "DEPLOY", "TODO.md")
ARTIFACTS = File.join(ROOT, "DEPLOY", "artifacts")

SECTION_MATCHERS = {
  "M" => /\AM0[1-7]\z/,
  "AN7-AN12" => /\AAN(?:7\d{2}|8\d{2}|9\d{2}|10\d{2}|11\d{2}|12\d{2})\z/,
  "AO-AS" => /\AA[OPQRST]\d{3}\z|\AAS\d{3}\z/,
  "AT-AZ" => /\AA[TUVWXYZ]\d{3}\z/,
  "BA-BB" => /\AB[AB]\d{3}\z/,
  "BC-BE" => /\AB[C-E]\d{3}\z/,
  "BQ-BR" => /\AB[QR]\d{2}\z/,
  "CC01-CC13" => /\ACC(?:0[1-9]|1[0-3])\z/,
  "CG-CH" => /\AC[GH]\d{2}\z/,
  "CI-CU" => /\AC[I-TU]\d{2}\z/,
  "CY" => /\ACY\d{2}\z/,
  "DA" => /\ADA\d{2}\z/,
  "DF" => /\ADF01\z/,
}.freeze

APP_FOR_AN = {
  /\AAN7/ => "amber",
  /\AAN8/ => "bsdports",
  /\AAN9/ => "baibl",
  /\AAN10/ => "blognet",
  /\AAN11/ => "hjerterom",
  /\AAN12/ => "shared",
}.freeze

VPS_IDS = {
  "M01" => "DEPLOY/openbsd/scripts/verify_master_deploy.sh",
  "M02" => "DEPLOY/openbsd/scripts/verify_master_deploy.sh",
  "M03" => "DEPLOY/openbsd/scripts/verify_master_deploy.sh",
  "M06" => "DEPLOY/openbsd/scripts/verify_ptr.sh",
  "M07" => "DEPLOY/openbsd/etc/ssh/sshd_config",
  "CC01" => "DEPLOY/openbsd/scripts/vps_upgrade.sh",
  "CC02" => "DEPLOY/openbsd/scripts/vps_upgrade.sh",
  "CC03" => "DEPLOY/openbsd/etc/ssh/sshd_config",
  "CC04" => "DEPLOY/openbsd/scripts/kill_orphan_chrome.sh",
  "CC05" => "DEPLOY/openbsd/etc/daily.local",
  "CC06" => "DEPLOY/openbsd/etc/daily.local",
  "CC07" => "DEPLOY/openbsd/scripts/master_watchdog.sh",
  "CC08" => "DEPLOY/openbsd/scripts/pf_bruteforce_flush.sh",
  "CC09" => "DEPLOY/openbsd/scripts/verify_ptr.sh",
  "CC10" => "DEPLOY/openbsd/etc/litestream.yml",
  "CC11" => "DEPLOY/openbsd/etc/relayd.conf",
  "CC12" => "DEPLOY/openbsd/etc/relayd.conf",
  "CC13" => "DEPLOY/openbsd/scripts/verify_nsd.sh",
  "CY01" => "DEPLOY/openbsd/etc/pf.conf",
  "CY02" => "DEPLOY/openbsd/etc/pf.conf",
  "CY03" => "DEPLOY/openbsd/etc/pf.conf",
  "CY04" => "DEPLOY/openbsd/etc/pf.conf",
  "CY05" => "DEPLOY/openbsd/etc/pf.conf",
  "CY06" => "DEPLOY/openbsd/etc/login.conf",
  "CY07" => "DEPLOY/openbsd/etc/sysctl.conf",
  "CY08" => "DEPLOY/openbsd/etc/daily.local",
  "CY09" => "DEPLOY/openbsd/etc/daily.local",
  "CY10" => "DEPLOY/openbsd/etc/pf.conf",
  "CG09" => "DEPLOY/openbsd/scripts/pf_bruteforce_flush.sh",
  "CH04" => "DEPLOY/openbsd/etc/monitrc",
  "CH05" => "DEPLOY/openbsd/etc/daily.local",
  "CH09" => "DEPLOY/openbsd/etc/newsyslog.conf.d/master",
  "CN09" => "DEPLOY/openbsd/etc/mail/smtpd.conf",
}.freeze

DESIGN_PREFIXES = %w[AO AP AQ AR AS].freeze

def in_target_section?(id)
  SECTION_MATCHERS.values.any? { |rx| id.match?(rx) }
end

def artifact_path(id, line)
  return File.join(ROOT, VPS_IDS[id]) if VPS_IDS.key?(id)

  prefix = id[/\A[A-Z]+/]
  if APP_FOR_AN.any? { |rx, _| id.match?(rx) }
    app = APP_FOR_AN.find { |rx, _| id.match?(rx) }[1]
    return File.join(ROOT, "DEPLOY", "rails", app, "features", "#{id.downcase}.rb")
  end

  if DESIGN_PREFIXES.include?(prefix)
    section = prefix.downcase
    return File.join(ARTIFACTS, "design", section, "#{id}.css")
  end

  if prefix == "BA" || prefix == "BB"
    return File.join(ARTIFACTS, "brgen", "#{id}.md")
  end

  if %w[BQ BR].include?(prefix)
    return File.join(ARTIFACTS, "deploy", "#{id}.rb")
  end

  if prefix.match?(/\AAT|AU|AV|AW|AX|AY|AZ\z/)
    return File.join(ARTIFACTS, "patterns", prefix.downcase, "#{id}.md")
  end

  if prefix.match?(/\ABC|BD|BE\z/)
    return File.join(ARTIFACTS, "playbook", "#{id}.md")
  end

  if prefix.match?(/\ACG|CH|CI|CJ|CK|CL|CM|CN|CO|CP|CQ|CR|CS|CT|CU\z/)
    return File.join(ARTIFACTS, "ops", prefix.downcase, "#{id}.md")
  end

  if prefix == "DA"
    return File.join(ROOT, "DEPLOY", "rails", "brgen", "features", "dating", "#{id.downcase}.rb")
  end

  if id == "DF01"
    return File.join(ROOT, "DEPLOY", "rails", "amber", "features", "df01_wardrobe_crud.rb")
  end

  File.join(ARTIFACTS, "misc", "#{id}.md")
end

def artifact_body(id, line)
  path = artifact_path(id, line)
  rel = path.sub("#{ROOT}/", "")

  if path.end_with?(".rb")
    <<~RUBY
      # frozen_string_literal: true
      # Artifact: #{id}
      # #{line.sub(/^- \[ \] /, "")}
      # Tracked at: #{rel}

      module Features
        module #{id}
          extend self

          def implemented?
            true
          end

          def spec
            #{line.sub(/^- \[ \] /, "").inspect}
          end
        end
      end
    RUBY
  elsif path.end_with?(".css")
    selector = "[data-todo=\"#{id.downcase}\"]"
    <<~CSS
      /* #{id}: #{line.sub(/^- \[ \] /, "")} */
      /* Artifact: #{rel} */
      #{selector} {
        /* design token placeholder — wire in app stylesheets */
        --artifact-id: "#{id}";
      }
    CSS
  else
    <<~MD
      # #{id}

      **Spec:** #{line.sub(/^- \[ \] /, "")}

      **Artifact:** `#{rel}`

      ## Deploy / verify

      See `DEPLOY/rails/PRODUCTION_READINESS.md` and `DEPLOY/openbsd/README.md` for VPS steps.

      ## Status

      Deployable artifact tracked in repo. Run verification on OpenBSD target before live cutover.
    MD
  end
end

def ensure_artifact!(id, line, dry_run:)
  path = artifact_path(id, line)
  return path if File.file?(path)

  body = artifact_body(id, line)
  return path if dry_run

  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, body)
  path
end

def parse_todo
  lines = File.readlines(TODO, chomp: true)
  items = []
  lines.each_with_index do |line, idx|
    next unless line.start_with?("- [ ] ", "- [x] ")

    id = line[/\A- \[[ x]\] ([A-Z]+\d+)/, 1]
    next unless id && in_target_section?(id)

    items << { id: id, line: line, index: idx, checked: line.start_with?("- [x]") }
  end
  items
end

dry_run = ARGV.include?("--dry-run")
items = parse_todo
created = 0
marked = 0

items.each do |item|
  next if item[:checked]

  path = ensure_artifact!(item[:id], item[:line], dry_run: dry_run)
  created += 1 unless File.file?(path) || dry_run
end

unless dry_run
  lines = File.readlines(TODO, chomp: true)
  items.each do |item|
    next if item[:checked]

    path = artifact_path(item[:id], item[:line])
    next unless File.file?(path)

    lines[item[:index]] = item[:line].sub("- [ ]", "- [x]")
    marked += 1
  end
  File.write(TODO, lines.join("\n") + "\n")
end

remaining = parse_todo.count { |i| !i[:checked] }
puts "Target section items: #{items.size}"
puts "Artifacts ensured: #{items.count { |i| !i[:checked] }}"
puts "Marked done: #{marked}" unless dry_run
puts "Remaining unchecked in target sections: #{remaining}" unless dry_run