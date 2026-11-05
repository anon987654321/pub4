# frozen_string_literal: true

# The constants and readers deploy_checks_contract_test.rb shares with the tests split
# out of it to keep each file under its length ceiling.
module DeployChecksContractSources
  ROOT = File.expand_path("../..", __dir__)
  REPO_ROOT = File.expand_path("../../..", __dir__)
  OPENBSD_ROOT = File.join(REPO_ROOT, "OPENBSD")
  MASTER_CHECKS = File.join(REPO_ROOT, "MASTER", "checks")

  CHECKS = YAML.safe_load_file(File.join(MASTER_CHECKS, "checks.yml")).freeze

  # A registered check that nothing runs.
  #
  # A check runs when some script names it, names the composite that covers it, or
  # runs `runner.rb --all`, which reaches every check with no covered_by parent;
  # bin/operator check does that through Operator::CheckChain. dns_zones predated
  # that and was the one none of these applied to: registered in checks.yml, complete, and never once executed. When
  # it finally was, it hard-failed on a claim that was not true — one dropped UDP
  # packet out of ~500 queries, reported as a missing DNS record — because a check
  # nobody runs is also a check nobody has seen be wrong.
  #
  # A count would have said 47 checks and meant 46. This asks the question the
  # count cannot.
  CALLER_GLOBS = %w[OPENBSD/bin/* OPENBSD/*.sh OPENBSD/*.rb OPENBSD/lib/*.rb
                    RAILS/*.sh MASTER/bin/* MASTER/lib/operator/*.rb bin/*].freeze

  # Comment lines are stripped first, and that is not tidiness. Written without
  # it, this test passed with the wiring deleted — because the commit that added
  # the wiring also added a comment saying the word "dns_zones", and prose about
  # a check satisfied a check for whether anything runs it. Ruby and zsh share the
  # `#` comment marker, which is the whole of what these callers are.
  def caller_source
    CALLER_GLOBS.flat_map { |glob| Dir[File.join(REPO_ROOT, glob)] }
                .select { |path| File.file?(path) }
                .map { |path| File.read(path, encoding: "UTF-8") }
                .join("\n")
                .lines.reject { |line| line.match?(/\A\s*#/) }.join
  end

  # Where a check's implementation is, which is not always under checks/. A require
  # naming a tree resolves from the repo root, the way runner.rb resolves it: the
  # checks that measure MASTER's face and the ones that measure the box live with
  # their subject, and only their row lives here.
  def check_file(row)
    required = row.fetch("require")
    base = required.start_with?("MASTER/", "OPENBSD/", "STUDIO/") ? File.expand_path("..", ROOT) : File.join(MASTER_CHECKS)
    File.join(base, required)
  end
end
