class InviteCodesController < ApplicationController
  before_action :ensure_self_hosted

  # O #create ja exigia admin (levantando StandardError). O #index nao exigia
  # nada: qualquer usuario logado listava os codigos validos da instancia -- e
  # um codigo vale por uma conta nova no servidor, entao listar e, na pratica,
  # poder convidar.
  #
  # Quem entra na instancia e decisao de administracao, igual ao resto de
  # settings/hosting (que ja exige admin desde o fix anterior).
  before_action :ensure_admin

  def index
    @invite_codes = InviteCode.all
  end

  def create
    InviteCode.generate!
    redirect_back_or_to invite_codes_path, notice: t(".success")
  end

  # Revoga um codigo ainda nao usado.
  #
  # Sem isto, um codigo gerado por engano -- ou um link que foi para o grupo
  # errado -- so saia do ar quando alguem o usasse, ou seja, exatamente quando
  # ja era tarde. E o codigo nao expira sozinho.
  def destroy
    InviteCode.find(params[:id]).destroy!

    redirect_back_or_to invite_codes_path, notice: t(".success")
  end

  private

    def ensure_self_hosted
      redirect_to root_path unless self_hosted?
    end

    def ensure_admin
      # 404 em vez de redirect com aviso: para quem nao e admin, este recurso
      # nao existe. Um aviso "voce nao pode ver os codigos" ja confirmaria que
      # ha codigos aqui.
      raise ActiveRecord::RecordNotFound unless Current.user.admin?
    end
end
