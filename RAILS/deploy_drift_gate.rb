#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/deploy_drift_gate"

# The message is "no drift", not "everything is deployed": off the deploy
# host there are no stamps to read, and the warning above says so. A gate
# should not claim more than it checked.
Deploy::DeployDriftGate.run.report!("ok: no deploy drift detected")
