class Goal < ApplicationRecord
  include Monetizable

  COLORS = Category::COLORS
  ICONS = Category.icon_codes

  belongs_to :family
  # Nucleo: a meta liga a UMA conta e usa o SALDO dela. Sem earmark, sem
  # pledge, sem investment-backing (isso fica para depois).
  belongs_to :account

  validates :name, presence: true, length: { maximum: 255 }
  validates :target_amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :icon, inclusion: { in: ICONS, allow_nil: true }
  validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }, allow_nil: true
  validate :target_date_not_in_past, on: :create
  # A conta ligada TEM que ser da mesma familia. Sem isto, `account_id` no
  # mass-assignment permitiria ligar a meta a conta de outra familia e vazar o
  # saldo alheio pelo progresso (IDOR). Brakeman aponta o account_id no permit;
  # esta e a defesa real, que cobre create e update.
  validate :account_belongs_to_family

  monetize :target_amount, :monthly_target_amount

  scope :alphabetically, -> { order(Arel.sql("LOWER(name) ASC")) }

  # Saldo atual da conta ligada, na moeda da meta.
  def current_amount
    account&.balance.to_d
  end

  def current_amount_money
    Money.new(current_amount, currency)
  end

  def remaining_amount
    [ target_amount.to_d - current_amount, 0 ].max
  end

  def remaining_amount_money
    Money.new(remaining_amount, currency)
  end

  def reached?
    current_amount >= target_amount.to_d
  end

  # Progresso em % (inteiro 0..100). 100 apenas quando a meta e atingida;
  # caso contrario satura em 99 para nao "arredondar para cheio" cedo demais.
  def progress_percent
    return 100 if reached?
    return 0 if target_amount.to_d.zero?

    ((current_amount / target_amount.to_d) * 100).floor.clamp(0, 99)
  end

  # Meses restantes ate a data-alvo (fracionario, precisao de dia).
  def months_remaining
    return nil unless target_date

    [ (target_date - Date.current).to_i / 30.0, 0.0 ].max
  end

  # Quanto falta poupar por mes para bater a meta na data-alvo.
  def monthly_target_amount
    return nil if target_date.nil?
    return remaining_amount if months_remaining.to_d.zero?

    (remaining_amount / months_remaining.to_d).ceil(2)
  end

  # Fracao do prazo ja decorrida (0.0..1.0), de created_at ate target_date.
  # Base da projecao/status linear simples. nil quando nao ha data-alvo.
  def elapsed_ratio
    return nil if target_date.nil?

    total = (target_date - created_at.to_date).to_f
    return 1.0 if total <= 0

    ((Date.current - created_at.to_date).to_f / total).clamp(0.0, 1.0)
  end

  # Quanto deveria ter poupado ate agora para estar no ritmo (linear).
  def expected_amount_now
    return 0.to_d if target_date.nil?

    (target_amount.to_d * elapsed_ratio.to_d)
  end

  # Projecao simples: extrapola o saldo atual no ritmo medio desde a criacao
  # ate a data-alvo. Sem historico de transacoes, sem rede.
  def projected_amount
    return current_amount if target_date.nil?

    ratio = elapsed_ratio
    return current_amount if ratio.nil? || ratio <= 0

    [ current_amount / ratio.to_d, current_amount ].max
  end

  def projected_amount_money
    Money.new(projected_amount, currency)
  end

  # Nucleo do status derivado do saldo vs data-alvo:
  #   :reached  -> saldo >= alvo
  #   :on_track -> sem data-alvo, OU no ritmo (saldo >= esperado ate hoje)
  #   :behind   -> tem data-alvo e esta abaixo do esperado ate hoje
  def status
    return :reached if reached?
    return :on_track if target_date.nil?

    current_amount >= expected_amount_now ? :on_track : :behind
  end

  private
    def target_date_not_in_past
      return if target_date.nil?

      errors.add(:target_date, :in_past) if target_date < Date.current
    end

    def account_belongs_to_family
      return if account.blank? || family.blank?

      errors.add(:account, :invalid) unless account.family_id == family_id
    end
end
