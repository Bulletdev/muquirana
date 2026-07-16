class InviteCode < ApplicationRecord
  # Quem entrou usando este codigo. A relacao vive do lado do usuario porque
  # agora sao varios por codigo -- cada conta veio de um convite.
  has_many :users, dependent: :nullify

  before_validation :generate_token, on: :create

  validates :max_uses, numericality: { only_integer: true, greater_than: 0 }

  scope :active, -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }
  scope :recent_first, -> { order(created_at: :desc) }

  class << self
    # Responde "este codigo ainda vale?", SEM consumir.
    #
    # Nao consome porque isto roda num before_action, antes de o usuario ser
    # salvo: um cadastro que falha na validacao nao pode gastar um uso do
    # convite de quem ainda vai tentar.
    def claimable(token)
      codigo = active.find_by(token: token&.downcase)
      codigo if codigo&.available?
    end

    def claim!(token)
      claimable(token).present?
    end

    def generate!(max_uses: 1)
      create!(max_uses: max_uses).token
    end
  end

  def available?
    !revoked? && uses_count < max_uses
  end

  def revoked?
    revoked_at.present?
  end

  def exhausted?
    uses_count >= max_uses
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  # Consome um uso e registra QUEM usou.
  #
  # O UPDATE carrega a condicao `uses_count < max_uses`: a checagem e a escrita
  # viram uma instrucao so, entao dois cadastros simultaneos na ultima vaga nao
  # passam os dois -- o segundo atualiza 0 linhas e recebe false. Ler, comparar
  # em Ruby e depois gravar deixaria essa janela aberta.
  #
  # O uses_count e a autoridade sobre "ainda pode": e ele que o UPDATE trava.
  # A relacao com users e para exibir quem entrou. Se uma conta for excluida, a
  # vaga continua gasta -- e o certo, ela foi usada.
  def mark_used!(user)
    consumido = self.class
                    .active
                    .where(id: id)
                    .where("uses_count < max_uses")
                    .update_all("uses_count = uses_count + 1") == 1

    user.update!(invite_code: self) if consumido
    consumido
  end

  private

    def generate_token
      loop do
        self.token = SecureRandom.hex(4)
        break token unless self.class.exists?(token: token)
      end
    end
end
