class InviteCodesController < ApplicationController
  # Teto de usos por link. Acima disso nao e mais "convidar", e deixar o
  # cadastro aberto -- e para isso ja existe o `require_invite_for_signup`, que
  # e uma decisao explicita e reversivel num clique.
  MAX_USES_LIMIT = 100

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
    @invite_codes = InviteCode.recent_first
  end

  def create
    InviteCode.generate!(max_uses: max_uses_param)
    redirect_back_or_to invite_codes_path, notice: t(".success")
  end

  # Revoga em vez de destruir.
  #
  # O codigo agora vale para varias pessoas e cada conta aponta para o convite
  # de onde veio (users.invite_code_id). Destruir a linha apagaria justamente o
  # registro de quem entrou -- que e a informacao que nao existia antes. Revogar
  # tira o link do ar e preserva o historico.
  def destroy
    InviteCode.find(params[:id]).revoke!

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

    # Quantas pessoas o link aceita. Vem de um <select> no formulario, entao e
    # input do usuario: `params[:max_uses]` pode ser "abc", "-1", "999999" ou
    # nada.
    #
    # O teto nao e paranoia com o admin: e um link que pode vazar. Um convite
    # para 100 mil pessoas nao e um convite, e um cadastro aberto -- e para isso
    # ja existe o botao de desligar a exigencia de convite, que e explicito.
    def max_uses_param
      valor = params[:max_uses].to_i

      return 1 if valor < 1

      [ valor, MAX_USES_LIMIT ].min
    end
end
