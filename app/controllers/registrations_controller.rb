class RegistrationsController < ApplicationController
  skip_authentication

  layout "auth"

  before_action :set_user, only: :create
  before_action :set_invitation
  before_action :claim_invite_code, only: :create, if: :invite_code_required?
  before_action :validate_password_requirements, only: :create

  def new
    @user = User.new(email: @invitation&.email)
  end

  def create
    if @invitation
      @user.family = @invitation.family
      @user.role = @invitation.role
      @user.email = @invitation.email
    else
      family = Family.new
      @user.family = family
      @user.role = :admin
    end

    if @user.save
      @invitation&.update!(accepted_at: Time.current)

      # O codigo so e consumido AGORA, com o usuario ja salvo -- assim fica
      # registrado quem o usou, e um cadastro que falha na validacao nao
      # queima o convite de quem ainda vai tentar de novo.
      #
      # Se mark_used! devolver false, outro cadastro consumiu o mesmo codigo
      # entre a validacao e este ponto. A conta ja existe e nao ha o que
      # desfazer com seguranca; o registro fica para o admin ver na tela de
      # hospedagem, onde o codigo aparece com o primeiro que o usou.
      @invite_code&.mark_used!(@user)

      @session = create_session_for(@user)
      redirect_to root_path, notice: t(".success")
    else
      render :new, status: :unprocessable_entity, alert: t(".failure")
    end
  end

  private

    def set_invitation
      token = params[:invitation]
      token ||= params[:user][:invitation] if params[:user].present?
      @invitation = Invitation.pending.find_by(token: token)
    end

    def set_user
      @user = User.new user_params.except(:invite_code, :invitation)
    end

    def user_params(specific_param = nil)
      params = self.params.require(:user).permit(:name, :email, :password, :password_confirmation, :invite_code, :invitation)
      specific_param ? params[specific_param] : params
    end

    # Valida o codigo e guarda o registro para o #create consumir depois do
    # save. Nao consome aqui: veja o comentario em InviteCode.claimable.
    def claim_invite_code
      @invite_code = InviteCode.claimable(params[:user][:invite_code])

      if @invite_code.nil?
        redirect_to new_registration_path, alert: t("registrations.create.invalid_invite_code")
      end
    end

    def validate_password_requirements
      password = user_params[:password]
      return if password.blank? # Let Rails built-in validations handle blank passwords

      if password.length < 8
        @user.errors.add(:password, "must be at least 8 characters")
      end

      unless password.match?(/[A-Z]/) && password.match?(/[a-z]/)
        @user.errors.add(:password, "must include both uppercase and lowercase letters")
      end

      unless password.match?(/\d/)
        @user.errors.add(:password, "must include at least one number")
      end

      unless password.match?(/[!@#$%^&*(),.?":{}|<>]/)
        @user.errors.add(:password, "must include at least one special character")
      end

      if @user.errors.present?
        render :new, status: :unprocessable_entity
      end
    end
end
