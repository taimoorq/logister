# frozen_string_literal: true

class Api::V1::Cli::CapabilitiesController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false

  def show
    render json: Logister::CliCapabilities.call
  end
end
