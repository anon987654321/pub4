# frozen_string_literal: true

module MasterPaths
  ROOT = File.expand_path("..", __dir__)
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
