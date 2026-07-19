class Settings::AssistantsController < ApplicationController
  layout "settings"

  def show
    @user = Current.user
  end

  def update
    if Current.user.update(assistant_params)
      redirect_to settings_assistant_path, notice: t(".success")
    else
      @user = Current.user
      flash.now[:alert] = t(".failure")
      render :show, status: :unprocessable_entity
    end
  end

  private
    def assistant_params
      # Chaves de LLM proprias do usuario (BYOK). Em branco = remove (volta a
      # depender da chave da instancia, se o admin liberar).
      params.require(:user).permit(:openai_access_token, :anthropic_access_token)
    end
end
