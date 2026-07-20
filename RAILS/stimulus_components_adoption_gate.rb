#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/stimulus_components_gate"

Deploy::StimulusComponentsGate.run.report!("Stimulus Components adoption gate passed.")
