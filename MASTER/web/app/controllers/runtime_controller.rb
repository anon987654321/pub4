# frozen_string_literal: true

class RuntimeController < ApplicationController
  def catalog
    render json: Master::Ground::RuntimeCatalog.web_boot_payload
  end

  def config
    render json: Master::Ground::RuntimeCatalog.web_boot_payload
  end

  def topologies
    data = Master.load_yaml(Master.data_path("topologies.yml"), default: {})
    render json: data
  end
end