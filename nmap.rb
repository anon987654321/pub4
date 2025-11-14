#!/usr/bin/env ruby
# nmap.rb - Network security scanner with sensible defaults

#
# Installation:

#   OpenBSD: `doas pkg_add nmap ruby--3.2; gem install ruby-nmap`
#   Cygwin: `apt-cyg install nmap ruby ruby-devel; gem install ruby-nmap`
#   Termux: `pkg install nmap ruby; gem install ruby-nmap`
#
# Usage: ruby nmap.rb [--help | --verbose | --lang=english|norwegian | --prompt]
#   --help: Show this help message
#   --verbose: Log debugging to syslog (OpenBSD) or stdout (Cygwin/Termux)
#   --lang: Choose language (english or norwegian, default: english)
#   --prompt: Prompt for severity and attack type (default: full scan)
#
# Notes:
#   - Requires permission to scan target network
#   - Test with 127.0.0.1 or scanme.nmap.org
#   - Default scan: All ports, service/OS detection, vulnerabilities, aggressive
#   - OpenBSD: Uses pledge/unveil, doas for privileged scans
#   - Cygwin: Non-privileged scans, /cygdrive paths
#   - Termux: Non-privileged scans, termux-toast for errors
#
# Example Output (English, default mode):
#   Network security scanner
#   Target (IP/hostname): 127.0.0.1
#   Warning: Full scan detects vulnerabilities. Ensure permission to scan 127.0.0.1.
#   Scanning 127.0.0.1
#   Host: 127.0.0.1 (Up)
#     Port: 22/tcp ssh OpenSSH 8.9
#     Port: 80/tcp http Apache 2.4
#     Vuln: http-vuln-cve2017-5638 CVE-2017-5638
#   Scan completed in 10.2 seconds
#
# Example Output (Norwegian, verbose mode, --verbose --lang=norwegian):
#   [DEBUG] Oct 06 18:00:00 nmap[1234]: validate.info: Validating target: 127.0.0.1
#   [DEBUG] Oct 06 18:00:00 nmap[1234]: validate.info: Checking nmap...
#   [DEBUG] Oct 06 18:00:00 nmap[1234]: validate.info: nmap found
#   [DEBUG] Oct 06 18:00:00 nmap[1234]: validate.info: Checking doas...
#   [DEBUG] Oct 06 18:00:00 nmap[1234]: validate.info: doas found
#   Nettverkssikkerhetsskanner
#   Mål (IP/vertsnavn): 127.0.0.1
#   Advarsel: Full skanning oppdager sårbarheter. Sørg for tillatelse til å skanne 127.0.0.1.
#   [DEBUG] Oct 06 18:00:00 nmap[1234]: setup.info: Created temp file: /tmp/nmap_12345.xml
#   [DEBUG] Oct 06 18:00:00 nmap[1234]: setup.info: Full scan: SYN, all ports, service/OS, vuln scripts, fast
#   [DEBUG] Oct 06 18:00:00 nmap[1234]: setup.info: nmap args: {"output_xml"=>"/tmp/nmap_12345.xml", "targets"=>"127.0.0.1", "syn_scan"=>true, "ports"=>"1-65535", "service_scan"=>true, "os_fingerprint"=>true, "script"=>"vuln,exploit", "timing_template"=>4, "version_intensity"=>9}
#   Skanner 127.0.0.1
#   [DEBUG] Oct 06 18:00:00 nmap[1234]: scan.info: Starting scan...
#   [DEBUG] Oct 06 18:00:10 nmap[1234]: scan.info: Scan done in 10.2 seconds
#   [DEBUG] Oct 06 18:00:10 nmap[1234]: parse.info: Parsing XML...
#   [DEBUG] Oct 06 18:00:10 nmap[1234]: parse.info: Found 1 host
#   [DEBUG] Oct 06 18:00:10 nmap[1234]: parse.info: Host: 127.0.0.1 (up)
#   [DEBUG] Oct 06 18:00:10 nmap[1234]: parse.info: Open port: 22/tcp (ssh OpenSSH 8.9)
#   [DEBUG] Oct 06 18:00:10 nmap[1234]: parse.info: Open port: 80/tcp (http Apache 2.4)
#   [DEBUG] Oct 06 18:00:10 nmap[1234]: parse.info: Checking vulnerabilities...
#   [DEBUG] Oct 06 18:00:10 nmap[1234]: parse.info: Vulnerabilities on port 80: http-vuln-cve2017-5638, CVE-2017-5638
#   Vert: 127.0.0.1 (Oppe)
#     Port: 22/tcp ssh OpenSSH 8.9
#     Port: 80/tcp http Apache 2.4
#     Sårbarhet: http-vuln-cve2017-5638 CVE-2017-5638
#   Skanning fullført på 10.2 sekunder
#   [DEBUG] Oct 06 18:00:10 nmap[1234]: cleanup.info: Cleaning up: /tmp/nmap_12345.xml
#   [DEBUG] Oct 06 18:00:10 nmap[1234]: cleanup.info: Temp file removed
require "nmap/xml"
require "tempfile"
# Lock script for security (OpenBSD only)
# Why: Restricts access to files and network

if RUBY_PLATFORM.include?("openbsd")
  begin

    require "pledge"
    pledge.promises(:stdio, :rpath, :wpath, :cpath, :proc, :exec, :inet)
    require "unveil"
    unveil("/tmp", "rwc") # Temp file access
    unveil("/usr/local/bin/nmap", "rx") # nmap execution
    unveil("/usr/local/bin/doas", "rx") # doas execution
  rescue LoadError
  end
end
$verbose = ARGV.include?("--verbose")
$lang = ARGV.find { |arg| arg.start_with?("--lang=") }&.split("=")&.last || "english"
$lang = $lang.downcase
$prompt = ARGV.include?("--prompt")

# Log to syslog (OpenBSD) or stdout (Cygwin/Termux)
# Why: Tracks actions for debugging
def log(message, facility = "validate", level = "info")
  timestamp = Time.now.strftime("%b %d %H:%M:%S")

  hostname = `hostname`.chomp
  pid = Process.pid
  msg = "#{timestamp} #{hostname} nmap[#{pid}]: #{facility}.#{level}: #{message}"
  if RUBY_PLATFORM.include?("openbsd")
    system("logger -t nmap \"#{msg}\"")
  else
    puts "[DEBUG] #{msg}" if $verbose
  end
  system("termux-toast \"#{msg}\"") if RUBY_PLATFORM.include?("linux") && `uname -o`.chomp == "Android" && $verbose
end
# Translations for English and Norwegian
# Why: Provides clear messages in chosen language
TRANSLATIONS = {
  "english" => {

    title: "Network security scanner",
    prompt_target: "Target (IP/hostname)",
    no_target: "Error: No target specified",
    invalid_target: "Error: Invalid target format",
    severity_title: "Severity levels",
    severity_low: "Low: Basic port scan (100 ports, slow)",
    severity_medium: "Medium: Service detection (1000 ports)",
    severity_high: "High: OS detection, default scripts",
    severity_critical: "Critical: Vulnerability/exploit detection",
    prompt_severity: "Severity [Low/Medium/High/Critical]",
    invalid_severity: "Error: Invalid severity",
    attack_title: "Attack types",
    attack_normal: "Normal: Standard scan",
    attack_stealth: "Stealth: Slow, evades detection",
    attack_aggressive: "Aggressive: Fast, maximum information",
    prompt_attack: "Attack type [Normal/Stealth/Aggressive]",
    invalid_attack: "Error: Invalid attack type",
    scanning: ->(target) { "Scanning #{target}" },
    scanning_with: ->(target, severity, attack_type) { "Scanning #{target} (Severity: #{severity}, Type: #{attack_type})" },
    warning_critical: ->(target) { "Warning: Full scan detects vulnerabilities. Ensure permission to scan #{target}." },
    no_hosts: "No hosts found",
    host: ->(ip, status) { "Host: #{ip} (#{status})" },
    port: ->(number, protocol, service, version) { "  Port: #{number}/#{protocol} #{service}#{version}" },
    vuln: ->(id, cves) { "  Vuln: #{id} #{cves}" },
    scan_completed: ->(duration) { "Scan completed in #{duration} seconds" },
    no_nmap: "Error: nmap not found. Install it (OpenBSD: doas pkg_add nmap; Cygwin: apt-cyg install nmap; Termux: pkg install nmap)",
    nmap_failed: ->(msg) { "Error: nmap failed: #{msg}" },
    unexpected_error: ->(msg) { "Error: Unexpected failure: #{msg}" },
    debug_validating_target: ->(target) { "Validating target: #{target}" },
    debug_nmap_check: "Checking nmap...",
    debug_nmap_found: "nmap found",
    debug_doas_check: "Checking doas...",
    debug_doas_found: "doas found",
    debug_doas_missing: "doas not found; full scan may be limited",
    debug_temp_file: ->(path) { "Created temp file: #{path}" },
    debug_severity_low: "Low severity: SYN scan, top 100 ports, slow",
    debug_severity_medium: "Medium severity: SYN scan, service detection, top 1000 ports, fast",
    debug_severity_high: "High severity: SYN scan, service/OS detection, default scripts, faster",
    debug_severity_critical: "Full scan: SYN, all ports, service/OS, vuln scripts, fast",
    debug_attack_normal: "Normal mode: No changes",
    debug_attack_stealth: "Stealth mode: Slow, evades detection",
    debug_attack_aggressive: "Aggressive mode: OS detection, max detail",
    debug_args: ->(args) { "nmap args: #{args}" },
    debug_scan_start: "Starting scan...",
    debug_scan_duration: ->(duration) { "Scan done in #{duration} seconds" },
    debug_parse_xml: "Parsing XML...",
    debug_hosts_found: ->(count) { "Found #{count} host" },
    debug_host: ->(ip, status) { "Host: #{ip} (#{status})" },
    debug_port: ->(number, protocol, service, version) { "Open port: #{number}/#{protocol} (#{service}#{version})" },
    debug_vuln_check: "Checking vulnerabilities...",
    debug_vuln_found: ->(port, id, cves) { "Vulnerabilities on port #{port}: #{id}, #{cves}" },
    debug_cleanup: ->(path) { "Cleaning up: #{path}" },
    debug_cleanup_done: "Temp file removed"
  },
  "norwegian" => {
    title: "Nettverkssikkerhetsskanner",
    prompt_target: "Mål (IP/vertsnavn)",
    no_target: "Feil: Ingen mål spesifisert",
    invalid_target: "Feil: Ugyldig målformat",
    severity_title: "Alvorlighetsnivåer",
    severity_low: "Lav: Enkel portskanning (100 porter, sakte)",
    severity_medium: "Middels: Tjenestedeteksjon (1000 porter)",
    severity_high: "Høy: OS-deteksjon, standardskripter",
    severity_critical: "Kritisk: Sårbarhets-/utnyttelsesdeteksjon",
    prompt_severity: "Alvorlighet [Lav/Middels/Høy/Kritisk]",
    invalid_severity: "Feil: Ugyldig alvorlighet",
    attack_title: "Angrepstyper",
    attack_normal: "Normal: Standard skanning",
    attack_stealth: "Snik: Sakte, unngår deteksjon",
    attack_aggressive: "Aggressiv: Rask, maksimal informasjon",
    prompt_attack: "Angrepstype [Normal/Snik/Aggressiv]",
    invalid_attack: "Feil: Ugyldig angrepstype",
    scanning: ->(target) { "Skanner #{target}" },
    scanning_with: ->(target, severity, attack_type) { "Skanner #{target} (Alvorlighet: #{severity}, Type: #{attack_type})" },
    warning_critical: ->(target) { "Advarsel: Full skanning oppdager sårbarheter. Sørg for tillatelse til å skanne #{target}." },
    no_hosts: "Ingen verter funnet",
    host: ->(ip, status) { "Vert: #{ip} (#{status})" },
    port: ->(number, protocol, service, version) { "  Port: #{number}/#{protocol} #{service}#{version}" },
    vuln: ->(id, cves) { "  Sårbarhet: #{id} #{cves}" },
    scan_completed: ->(duration) { "Skanning fullført på #{duration} sekunder" },
    no_nmap: "Feil: nmap ikke funnet. Installer det (OpenBSD: doas pkg_add nmap; Cygwin: apt-cyg install nmap; Termux: pkg install nmap)",
    nmap_failed: ->(msg) { "Feil: nmap mislyktes: #{msg}" },
    unexpected_error: ->(msg) { "Feil: Uventet feil: #{msg}" },
    debug_validating_target: ->(target) { "Validerer mål: #{target}" },
    debug_nmap_check: "Sjekker nmap...",
    debug_nmap_found: "nmap funnet",
    debug_doas_check: "Sjekker doas...",
    debug_doas_found: "doas funnet",
    debug_doas_missing: "doas ikke funnet; full skanning kan være begrenset",
    debug_temp_file: ->(path) { "Created temp file: #{path}" },
    debug_severity_low: "Lav alvorlighet: SYN, topp 100 porter, sakte",
    debug_severity_medium: "Middels alvorlighet: SYN, tjenestedeteksjon, topp 1000 porter, rask",
    debug_severity_high: "Høy alvorlighet: SYN, tjeneste/OS, standardskripter, raskere",
    debug_severity_critical: "Full skanning: SYN, alle porter, tjeneste/OS, sårbarhetsskripter, rask",
    debug_attack_normal: "Normal modus: Ingen endringer",
    debug_attack_stealth: "Snikmodus: Sakte, unngår deteksjon",
    debug_attack_aggressive: "Aggressiv modus: OS-deteksjon, maks detalj",
    debug_args: ->(args) { "nmap-argumenter: #{args}" },
    debug_scan_start: "Starter skanning...",
    debug_scan_duration: ->(duration) { "Skanning ferdig på #{duration} sekunder" },
    debug_parse_xml: "Parser XML...",
    debug_hosts_found: ->(count) { "Fant #{count} vert" },
    debug_host: ->(ip, status) { "Vert: #{ip} (#{status})" },
    debug_port: ->(number, protocol, service, version) { "Åpen port: #{number}/#{protocol} (#{service}#{version})" },
    debug_vuln_check: "Sjekker sårbarheter...",
    debug_vuln_found: ->(port, id, cves) { "Sårbarheter på port #{port}: #{id}, #{cves}" },
    debug_cleanup: ->(path) { "Rydder opp: #{path}" },
    debug_cleanup_done: "Temp fil fjernet"
  }
}
# Validate language
# Why: Ensures valid language choice
unless TRANSLATIONS.key?($lang)
  log "Invalid language. Use --lang=english or --lang=norwegian", "validate", "error"

  abort "Error: Invalid language. Use --lang=english or --lang=norwegian"
end
T = TRANSLATIONS[$lang]
# Prompt for input
# Why: Gets user input like IP address
def prompt(msg)
  print "#{msg}: "

  gets.chomp
end
# Validate target
# Why: Ensures address is valid
def valid_target?(target)
  target =~ /^(?:(?:[0-9]{1,3}\.){3}[0-9]{1,3}|(?:[a-zA-Z0-9-]+\.)*[a-zA-Z0-9-]+)$/

end
# Check dependencies
# Why: Confirms nmap and doas availability
def check_requirements
  log T[:debug_nmap_check], "validate", "info"

  unless system("which nmap > /dev/null 2>&1")
    log T[:no_nmap], "validate", "error"
    abort T[:no_nmap]
  end
  log T[:debug_nmap_found], "validate", "info"
  if RUBY_PLATFORM.include?("openbsd")
    log T[:debug_doas_check], "validate", "info"
    if system("which doas > /dev/null 2>&1")
      log T[:debug_doas_found], "validate", "info"
    else
      log T[:debug_doas_missing], "validate", "warning"
    end
  end
end
# Perform scan
# Why: Scans for open ports, services, vulnerabilities
def scan(target, severity, attack_type)
  log T[:debug_validating_target].call(target), "validate", "info"

  unless valid_target?(target)
    log T[:invalid_target], "validate", "error"
    abort T[:invalid_target]
  end
  check_requirements
  # Setup temp file
  xml = Tempfile.new(["nmap", ".xml"])
  log T[:debug_temp_file].call(xml.path), "setup", "info"
  # Build scan arguments

  args = { output_xml: xml.path, targets: target }
  if $prompt
    case severity

    when "low"
      log T[:debug_severity_low], "setup", "info"
      args.merge!(syn_scan: true, top_ports: 100, timing_template: 2)
    when "medium"
      log T[:debug_severity_medium], "setup", "info"
      args.merge!(syn_scan: true, service_scan: true, top_ports: 1000, timing_template: 3)
    when "high"
      log T[:debug_severity_high], "setup", "info"
      args.merge!(syn_scan: true, service_scan: true, os_fingerprint: true, script: "default", timing_template: 4)
    when "critical"
      puts T[:warning_critical].call(target)
      log T[:debug_severity_critical], "setup", "info"
      args.merge!(syn_scan: true, ports: "1-65535", service_scan: true, os_fingerprint: true, script: "vuln,exploit", timing_template: 4)
    else
      log T[:invalid_severity], "validate", "error"
      abort T[:invalid_severity]
    end
    case attack_type
    when "stealth"
      log T[:debug_attack_stealth], "setup", "info"
      args[:timing_template] = 1
    when "aggressive"
      log T[:debug_attack_aggressive], "setup", "info"
      args.merge!(os_fingerprint: true, version_intensity: 9)
    when "normal"
      log T[:debug_attack_normal], "setup", "info"
    else
      log T[:invalid_attack], "validate", "error"
      abort T[:invalid_attack]
    end
  else
    puts T[:warning_critical].call(target)
    log T[:debug_severity_critical], "setup", "info"
    args.merge!(syn_scan: true, ports: "1-65535", service_scan: true, os_fingerprint: true, script: "vuln,exploit", timing_template: 4, version_intensity: 9)
  end
  log T[:debug_args].call(args.inspect), "setup", "info"
  # Run scan
  begin
    puts $prompt ? T[:scanning_with].call(target, severity.capitalize, attack_type.capitalize) : T[:scanning].call(target)

    log T[:debug_scan_start], "scan", "info"

    start = Time.now
    use_doas = (severity == "high" || severity == "critical" || !$prompt) && RUBY_PLATFORM.include?("openbsd")
    if use_doas && system("which doas > /dev/null 2>&1")
      log T[:debug_doas_found], "scan", "info"
      system("doas nmap #{args.map { |k, v| "--#{k.to_s.gsub('_', '-')}=#{v}" }.join(" ")} >/dev/null 2>&1")
    else
      log T[:debug_doas_missing], "scan", "warning" if use_doas
      system("nmap #{args.map { |k, v| "--#{k.to_s.gsub('_', '-')}=#{v}" }.join(" ")} >/dev/null 2>&1")
    end
    unless $?.success?
      log T[:nmap_failed].call("non-zero exit status"), "scan", "error"
      abort T[:nmap_failed].call("non-zero exit status")
    end
    duration = (Time.now - start).round(1)
    log T[:debug_scan_duration].call(duration), "scan", "info"
    # Parse results
    log T[:debug_parse_xml], "parse", "info"
    unless File.exist?(xml.path) && File.size?(xml.path)
      log T[:no_results], "parse", "error"

      abort T[:no_results]
    end
    Nmap::XML.open(xml.path) do |x|
      log T[:debug_hosts_found].call(x.hosts.size), "parse", "info"
      if x.hosts.empty?
        puts T[:no_hosts]
        return
      end
      x.each_host do |h|
        log T[:debug_host].call(h.ip, h.status), "parse", "info"
        puts T[:host].call(h.ip, h.status.capitalize)
        h.each_open_port do |p|
          svc = p.service.name || (T == TRANSLATIONS["english"] ? "Unknown" : "Ukjent")
          ver = p.service.version ? " #{p.service.version}" : ""
          log T[:debug_port].call(p.number, p.protocol, svc, ver), "parse", "info"
          puts T[:port].call(p.number, p.protocol, svc, ver)
        end
        if severity == "critical" || !$prompt
          log T[:debug_vuln_check], "parse", "info"
          h.each_port do |p|
            p.scripts.each do |id, s|
              cves = s.output.scan(/CVE-\d{4}-\d+/).uniq
              if cves.any?
                log T[:debug_vuln_found].call(p.number, id, cves.join(", ")), "parse", "info"
                puts T[:vuln].call(id, cves.join(" "))
              end
            end
          end
        end
      end
    end
    puts T[:scan_completed].call(duration)
  # Cleanup
  rescue StandardError => e
    log T[:unexpected_error].call(e.message), "error", "error"
    abort T[:unexpected_error].call(e.message)

  ensure
    log T[:debug_cleanup].call(xml.path), "cleanup", "info"
    xml.unlink if File.exist?(xml.path)
    log T[:debug_cleanup_done], "cleanup", "info"
  end
end
# Main script
# Why: Gets target and runs scan
if ARGV.include?("--help")
  puts <<~HELP

    #{T[:title]}
    Usage: ruby nmap.rb [--help | --verbose | --lang=english|norwegian | --prompt]
    Options:
      --help            #{T == TRANSLATIONS["english"] ? "Show this help" : "Vis denne hjelpen"}
      --verbose         #{T == TRANSLATIONS["english"] ? "Enable debug output" : "Aktiver feilsøkingsutdata"}
      --lang=english|norwegian  #{T == TRANSLATIONS["english"] ? "Set language" : "Sett språk"}
      --prompt          #{T == TRANSLATIONS["english"] ? "Prompt for severity and attack type" : "Spør om alvorlighet og angrepstype"}
    Prompts (with --prompt):
      #{T[:prompt_target]}: #{T == TRANSLATIONS["english"] ? "e.g., 127.0.0.1 or scanme.nmap.org" : "f.eks., 127.0.0.1 eller scanme.nmap.org"}
      #{T[:prompt_severity]}
      #{T[:prompt_attack]}
    Default: Full scan (all ports, service/OS detection, vulnerabilities, aggressive)
    Requirements:
      - nmap (OpenBSD: doas pkg_add nmap; Cygwin: apt-cyg install nmap; Termux: pkg install nmap)
      - ruby-nmap gem (gem install ruby-nmap)
    #{T == TRANSLATIONS["english"] ? "Note: Ensure permission to scan target." : "Merknad: Sørg for tillatelse til å skanne målet."}
  HELP
  exit
end
puts T[:title]
target = prompt(T[:prompt_target])
if target.empty?
  log T[:no_target], "validate", "error"

  abort T[:no_target]
end
# Optional prompts
if $prompt
  puts T[:severity_title]
  puts "  #{T[:severity_low]}"

  puts "  #{T[:severity_medium]}"
  puts "  #{T[:severity_high]}"
  puts "  #{T[:severity_critical]}"
  severity = prompt(T[:prompt_severity]).downcase
  severity = "medium" if severity.empty?
  unless %w[low medium high critical].include?(severity)
    log T[:invalid_severity], "validate", "error"
    abort T[:invalid_severity]
  end
  puts T[:attack_title]
  puts "  #{T[:attack_normal]}"
  puts "  #{T[:attack_stealth]}"
  puts "  #{T[:attack_aggressive]}"
  attack_type = prompt(T[:prompt_attack]).downcase
  attack_type = "normal" if attack_type.empty?
  unless %w[normal stealth aggressive].include?(attack_type)
    log T[:invalid_attack], "validate", "error"
    abort T[:invalid_attack]
  end
else
  severity = "critical"
  attack_type = "aggressive"
end
# Run scan
scan(target, severity, attack_type)
