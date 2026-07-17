class Settings::SecuritiesController < ApplicationController
  layout "settings"

  def show
    @encryption_unconfigured = Rails.application.config.app_mode.self_hosted? &&
      !ActiveRecordEncryptionConfig.explicitly_configured?
  end
end
