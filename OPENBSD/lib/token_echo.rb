# frozen_string_literal: true

# A line that writes output and carries a token value in a query string. A
# restart that prints `web: <url>/?token=<secret>` leaves the operator credential
# in ~/vps-deploy.log for anyone who reads it. Sending a token stays allowed: a
# curl or a Rack env builds a request, and no log reads that line.
#
# Its own file rather than three more defs in deploy_smoke_gate.rb: MASTER's
# self_test counts an OPENBSD Ruby file past ten defs as a god class and refuses
# to boot, and the smoke gate stood at ten. Scanning every tracked script is a
# different job from checking the relayd and httpd templates anyway.
module TokenEcho
  PATTERN = /token=(?:#\{|\$\{?\w|%s)/
  OUTPUT_VERB = /\b(?:puts|print|printf|echo|warn|logger|tee)\b|\$std(?:out|err)\b|\bSTD(?:OUT|ERR)\b/
  SCRIPT_EXTENSIONS = %w[.rb .sh .ksh .zsh .rake].freeze

  module_function

  def echoes(text, path)
    text.each_line.with_index(1).filter_map do |line, number|
      "#{path}:#{number}" if line.match?(PATTERN) && line.match?(OUTPUT_VERB)
    end
  end

  # Tracked scripts and every Ruby file, tests aside: a test that proves this
  # detector has to spell the line it refuses.
  def candidates(root)
    listed = IO.popen(["git", "-C", root, "ls-files", "-z"], err: File::NULL, &:read).to_s.split("\0")
    listed.select do |rel|
      next false if rel.match?(%r{(?:\A|/)(?:test|spec)/})

      path = File.join(root, rel)
      next false unless File.file?(path) && File.size(path) < 1_000_000

      SCRIPT_EXTENSIONS.include?(File.extname(rel)) || rel.include?("/rc.d/") ||
        (File.extname(rel).empty? && File.open(path) { |f| f.read(2) } == "#!")
    end
  end

  def check(failures, root)
    scripts = candidates(root)
    if scripts.empty?
      failures << "token echo: git ls-files listed no scripts under #{root}, so nothing was read"
      return
    end

    scripts.each do |rel|
      echoes(File.read(File.join(root, rel)).scrub, rel).each do |at|
        failures << "token echo: #{at} prints a token value — print the URL and point at /pair issue"
      end
    end
  end
end
