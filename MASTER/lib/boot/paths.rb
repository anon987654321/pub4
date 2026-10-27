# frozen_string_literal: true

# sprawl: deliberate — standalone-load contract. Four lib files require this
# with no boot order (Swallow's standalone use from MASTER/tools depends on it, see
# data/spine.yml 2026-08-11 +2); folding it into a boot file would make every
# standalone require pull early-boot code.
module MasterPaths
  ROOT = File.expand_path("../..", __dir__)
  REPO = File.expand_path("..", ROOT)
  DATA = File.join(ROOT, "data")
  REPORTS = File.join(ROOT, "reports")
  STATE = File.expand_path("~/.master")
  # The four governed trees, the one list every caller reads.
  TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze

  module_function

  def root = ROOT
  def repo = REPO
  def data(*parts) = File.join(DATA, *parts)
  def reports(*parts) = File.join(REPORTS, *parts)
  def state(*parts) = File.join(STATE, *parts)

  # The mode a private state directory is tightened to: others never keep access,
  # and the owner always has it. A directory handed to a group other than the
  # caller's own keeps that group's bits, because the hand-off is deliberate: on
  # vm23 MASTER/.master is dev:master so the master Rails app, running as master,
  # reads its config and reaches the TTS sockets, and a plain 0700 locked it out.
  # Where the directory carries the caller's own group this is base unchanged.
  def private_dir_mode(dir, base = 0o700)
    stat = File.stat(dir)
    return base if stat.gid == Process.egid

    base | (stat.mode & 0o2070)
  end
end
