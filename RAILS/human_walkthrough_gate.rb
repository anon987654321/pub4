#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../OPENBSD/lib/utf8"
require_relative "gates/lib/human_walkthrough_gate"

apps = Deploy::Inventory.new(root: Deploy::HumanWalkthroughGate::ROOT).apps
Deploy::HumanWalkthroughGate.run.report!(
  "Human walkthrough gate passed for #{apps.size} Rails apps."
)
