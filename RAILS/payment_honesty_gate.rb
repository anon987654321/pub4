#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/payment_honesty_gate"
Deploy::PaymentHonestyGate.run.report!("Payment honesty gate passed.")
