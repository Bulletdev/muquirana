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

    # US-07: chave/modelo Anthropic. Mesma regra do externo: so grava o que veio
    # no POST e nunca sobrescreve um valor definido por ENV (campo desabilitado).
    if hosting_params.key?(:anthropic_access_token) && ENV["ANTHROPIC_ACCESS_TOKEN"].blank? && ENV["ANTHROPIC_API_KEY"].blank?
      Setting.anthropic_access_token = hosting_params[:anthropic_access_token]
    end

    if hosting_params.key?(:anthropic_model) && ENV["ANTHROPIC_MODEL"].blank?
      Setting.anthropic_model = hosting_params[:anthropic_model]
    end

    # US-08: assistente externo self-hosted. So gravamos o campo que veio no
    # POST (o form de cada secao envia so os seus), e nunca sobrescrevemos um
    # valor definido por ENV -- ai o campo vai desabilitado na tela.
    if hosting_params.key?(:external_assistant_url) && ENV["EXTERNAL_ASSISTANT_URL"].blank?
      Setting.external_assistant_url = hosting_params[:external_assistant_url]
    end

    if hosting_params.key?(:external_assistant_token) && ENV["EXTERNAL_ASSISTANT_TOKEN"].blank?
      Setting.external_assistant_token = hosting_params[:external_assistant_token]
    end

    if hosting_params.key?(:external_assistant_model) && ENV["EXTERNAL_ASSISTANT_MODEL"].blank?
      Setting.external_assistant_model = hosting_params[:external_assistant_model]
    end

    if hosting_params.key?(:external_assistant_agent_id) && ENV["EXTERNAL_ASSISTANT_AGENT_ID"].blank?
      Setting.external_assistant_agent_id = hosting_params[:external_assistant_agent_id]
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
      params.require(:setting).permit(
        :require_invite_for_signup,
        :require_email_confirmation,
        :synth_api_key,
        :anthropic_access_token,
        :anthropic_model,
        :external_assistant_url,
        :external_assistant_token,
        :external_assistant_model,
        :external_assistant_agent_id
      )
    end

    def ensure_admin
      # Redireciona para uma pagina que o membro PODE acessar. Antes mandava para
      # settings_hosting_path -- a mesma pagina guardada por este before_action --
      # o que gerava loop infinito de redirect (ERR_TOO_MANY_REDIRECTS) em vez de
      # um bounce limpo.
      redirect_to settings_profile_path, alert: t("settings.hostings.not_authorized") unless Current.user.admin?
    end
end
