# frozen_string_literal: true

# sprawl: deliberate — standalone-load contract. Four lib files require this
# with no boot order (Swallow's standalone use from STUDIO depends on it, see
# data/spine.yml 2026-08-11 +2); folding it into a boot file would make every
# standalone require pull early-boot code.
module MasterPaths
  ROOT = File.expand_path("../..", __dir__)
  REPO = File.expand_path("..", ROOT)
  DATA = File.join(ROOT, "data")
  REPORTS = File.join(ROOT, "reports")
  STATE = File.expand_path("~/.master")

  module_function

  def root = ROOT
  def repo = REPO
  def data(*parts) = File.join(DATA, *parts)
  def reports(*parts) = File.join(REPORTS, *parts)
  def state(*parts) = File.join(STATE, *parts)
end
