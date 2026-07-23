#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../OPENBSD/lib/utf8"
require_relative "gates/lib/apps_yml_validator"

Deploy::AppsYmlValidator.run.report!("apps.yml validator: OK")
