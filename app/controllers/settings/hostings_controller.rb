class Settings::HostingsController < ApplicationController
  layout "settings"

  guard_feature unless: -> { self_hosted? }

  # O ensure_admin cobria APENAS o clear_cache -- a acao menos perigosa daqui.
  # O #update ficava aberto a qualquer usuario logado, e o Setting e GLOBAL da
  # instancia (RailsSettings::Base), nao da familia: um membro comum podia
  # desligar o require_invite_for_signup e reabrir o cadastro publico do
  # servidor inteiro, ou trocar a synth_api_key.
  #
  # O #show tambem entra: ele exibe o uso e a configuracao do provedor, que e
  # dado de administracao da instancia, nao do usuario.
  before_action :ensure_admin

  def show
    synth_provider = Provider::Registry.get_provider(:synth)
    @synth_usage = synth_provider&.usage
  end

  def update
    if hosting_params.key?(:require_invite_for_signup)
      Setting.require_invite_for_signup = hosting_params[:require_invite_for_signup]
    end

    if hosting_params.key?(:require_email_confirmation)
      Setting.require_email_confirmation = hosting_params[:require_email_confirmation]
    end

    if hosting_params.key?(:synth_api_key)
      Setting.synth_api_key = hosting_params[:synth_api_key]
    end

    redirect_to settings_hosting_path, notice: t(".success")
  rescue ActiveRecord::RecordInvalid => error
    flash.now[:alert] = t(".failure")
    render :show, status: :unprocessable_entity
  end

  def clear_cache
    DataCacheClearJob.perform_later(Current.family)
    redirect_to settings_hosting_path, notice: t(".cache_cleared")
  end

  private
    def hosting_params
      params.require(:setting).permit(:require_invite_for_signup, :require_email_confirmation, :synth_api_key)
    end

    def ensure_admin
      redirect_to settings_hosting_path, alert: t("settings.hostings.not_authorized") unless Current.user.admin?
    end
end
