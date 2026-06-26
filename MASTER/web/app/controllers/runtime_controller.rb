# frozen_string_literal: true

require "json"

class RuntimeController < ApplicationController
  skip_before_action :require_container!

  def catalog
    render_runtime_json(Master::Ground::RuntimeCatalog.web_boot_payload)
  end

  def boot_config
    render_runtime_json(Master::Ground::RuntimeCatalog.web_boot_payload)
  end

  def topologies
    data = Master.load_yaml(Master.data_path("topologies.yml"), default: {})
    render_runtime_json(data)
  end

  private

  def render_runtime_json(payload)
    render body: JSON.generate(payload), content_type: "application/json"
  end
end