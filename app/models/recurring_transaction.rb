class RecurringTransaction < ApplicationRecord
  include Monetizable

  belongs_to :family
  belongs_to :account, optional: true
  belongs_to :merchant, optional: true, class_name: "FamilyMerchant"

  monetize :amount
  monetize :expected_amount_min, allow_nil: true
  monetize :expected_amount_max, allow_nil: true
  monetize :expected_amount_avg, allow_nil: true

  enum :status, { active: "active", inactive: "inactive" }

  validates :amount, presence: true
  validates :currency, presence: true
  validates :expected_day_of_month, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 31 }
  validates :occurrence_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :merchant_or_name_present
  validate :amount_variance_consistency

  scope :for_family, ->(family) { where(family: family) }
  scope :expected_soon, -> { active.where("next_expected_date <= ?", 1.month.from_now) }

  def merchant_or_name_present
    if merchant_id.blank? && name.blank?
      errors.add(:base, :merchant_or_name_required)
    end
  end

  def amount_variance_consistency
    return unless manual?

    if expected_amount_min.present? && expected_amount_max.present? && expected_amount_min > expected_amount_max
      errors.add(:expected_amount_min, "cannot be greater than expected_amount_max")
    end
  end

  # Agenda a identificacao de padroes (com debounce) para rodar apos os syncs.
  def self.identify_patterns_for(family)
    IdentifyRecurringTransactionsJob.schedule_for(family)
    0 # retorna na hora; a contagem real fica a cargo do job
  end

  # Identificacao sincrona (para o gatilho manual da UI).
  def self.identify_patterns_for!(family)
    Identifier.new(family).identify_recurring_patterns
  end

  def self.cleanup_stale_for(family)
    Cleaner.new(family).cleanup_stale_transactions
  end

  # Cria uma recorrencia manual a partir de uma transacao existente. Calcula a
  # faixa de variacao a partir dos ultimos 6 meses de lancamentos parecidos.
  def self.create_from_transaction(transaction)
    entry = transaction.entry
    family = entry.account.family
    expected_day = entry.date.day

    matching_amounts = find_matching_transaction_amounts(
      family: family,
      merchant_id: transaction.merchant_id,
      name: transaction.merchant_id.present? ? nil : entry.name,
      currency: entry.currency,
      expected_day: expected_day,
      lookback_months: 6,
      account: entry.account
    )

    expected_min = expected_max = expected_avg = nil
    if matching_amounts.size > 1
      expected_min = matching_amounts.min
      expected_max = matching_amounts.max
      expected_avg = matching_amounts.sum / matching_amounts.size
    elsif matching_amounts.size == 1
      expected_min = expected_max = expected_avg = matching_amounts.first
    end

    next_expected = calculate_next_expected_date_from_today(expected_day)

    create!(
      family: family,
      account: entry.account,
      merchant_id: transaction.merchant_id,
      name: transaction.merchant_id.present? ? nil : entry.name,
      amount: entry.amount,
      currency: entry.currency,
      expected_day_of_month: expected_day,
      last_occurrence_date: entry.date,
      next_expected_date: next_expected,
      status: "active",
      occurrence_count: [ matching_amounts.size, 1 ].max,
      manual: true,
      expected_amount_min: expected_min,
      expected_amount_max: expected_max,
      expected_amount_avg: expected_avg
    )
  end

  def self.find_matching_transaction_entries(family:, merchant_id:, name:, currency:, expected_day:, lookback_months: 6, account: nil)
    lookback_date = lookback_months.months.ago.to_date

    entries = (account.present? ? account.entries : family.entries)
      .where(entryable_type: "Transaction")
      .where(currency: currency)
      .where("entries.date >= ?", lookback_date)
      .where("EXTRACT(DAY FROM entries.date) BETWEEN ? AND ?",
             [ expected_day - 2, 1 ].max,
             [ expected_day + 2, 31 ].min)
      .order(date: :desc)

    if merchant_id.present?
      entries
        .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
        .where(transactions: { merchant_id: merchant_id })
        .to_a
    else
      entries.where(name: name).to_a
    end
  end

  def self.find_matching_transaction_amounts(family:, merchant_id:, name:, currency:, expected_day:, lookback_months: 6, account: nil)
    find_matching_transaction_entries(
      family: family,
      merchant_id: merchant_id,
      name: name,
      currency: currency,
      expected_day: expected_day,
      lookback_months: lookback_months,
      account: account
    ).map(&:amount)
  end

  def self.calculate_next_expected_date_from_today(expected_day)
    today = Date.current

    begin
      this_month_date = Date.new(today.year, today.month, expected_day)
      return this_month_date if this_month_date > today
    rescue ArgumentError
      # Dia nao existe neste mes (ex.: 31 em fevereiro)
    end

    calculate_next_expected_date_for(today, expected_day)
  end

  def self.calculate_next_expected_date_for(from_date, expected_day)
    next_month = from_date.next_month
    begin
      Date.new(next_month.year, next_month.month, expected_day)
    rescue ArgumentError
      next_month.end_of_month
    end
  end

  # Lancamentos que casam com este padrao (mesmo valor/cadencia).
  def matching_transactions
    base = account.present? ? account.entries : family.entries
    entries = day_of_month_scope(
      amount_window_scope(base.where(entryable_type: "Transaction").where(currency: currency))
    ).order(date: :desc)

    if merchant_id.present?
      entries.select do |entry|
        entry.entryable.is_a?(Transaction) && entry.entryable.merchant_id == merchant_id
      end
    else
      entries.where(name: name)
    end
  end

  def has_amount_variance?
    expected_amount_min.present? && expected_amount_max.present?
  end

  def should_be_inactive?
    return false if last_occurrence_date.nil?
    threshold = manual? ? 6.months.ago : 2.months.ago
    last_occurrence_date < threshold
  end

  def mark_inactive!
    update!(status: "inactive")
  end

  def mark_active!
    update!(status: "active")
  end

  # Calcula a proxima data prevista a partir da ultima ocorrencia.
  def calculate_next_expected_date(from_date = last_occurrence_date)
    next_month = from_date.next_month
    begin
      Date.new(next_month.year, next_month.month, expected_day_of_month)
    rescue ArgumentError
      next_month.end_of_month
    end
  end

  private
    def amount_window_scope(relation)
      if manual? && has_amount_variance?
        relation.where("entries.amount BETWEEN ? AND ?", expected_amount_min, expected_amount_max)
      else
        relation.where("entries.amount = ?", amount)
      end
    end

    def day_of_month_scope(relation)
      relation.where("EXTRACT(DAY FROM entries.date) BETWEEN ? AND ?",
                     [ expected_day_of_month - 2, 1 ].max,
                     [ expected_day_of_month + 2, 31 ].min)
    end

    def monetizable_currency
      currency
    end
end
