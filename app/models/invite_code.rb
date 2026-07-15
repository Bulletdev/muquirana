class InviteCode < ApplicationRecord
  belongs_to :used_by, class_name: "User", optional: true

  before_validation :generate_token, on: :create

  scope :unused, -> { where(used_at: nil) }
  scope :used, -> { where.not(used_at: nil) }
  scope :recent_first, -> { order(created_at: :desc) }

  class << self
    # Responde "este codigo vale?", SEM consumir.
    #
    # O comportamento anterior era `destroy!` aqui. Como isto roda num
    # before_action -- antes de o usuario ser salvo -- um cadastro que falhava
    # na validacao (senha fraca, e-mail repetido) destruia o codigo do mesmo
    # jeito: a pessoa convidada ficava travada para sempre e o link morria sem
    # explicacao.
    #
    # Quem consome e o `mark_used!`, depois de o usuario existir de fato.
    def claimable(token)
      unused.find_by(token: token&.downcase)
    end

    def claim!(token)
      claimable(token).present?
    end

    def generate!
      create!.token
    end
  end

  def used?
    used_at.present?
  end

  # Consome o codigo registrando QUEM usou. O registro nao e mais apagado: era
  # por isso que o admin nao tinha nenhuma informacao sobre quem entrou na
  # instancia dele.
  #
  # `unused.where(id:).update_all` em vez de `update!`: a checagem de used_at e
  # a escrita viram uma instrucao so, entao dois cadastros simultaneos com o
  # mesmo codigo nao passam os dois -- o segundo atualiza 0 linhas e recebe
  # false.
  def mark_used!(user)
    self.class.unused.where(id: id).update_all(used_at: Time.current, used_by_id: user.id) == 1
  end

  private

    def generate_token
      loop do
        self.token = SecureRandom.hex(4)
        break token unless self.class.exists?(token: token)
      end
    end
end
