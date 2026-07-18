class Transaction < ApplicationRecord
  include Entryable, Transferable, Ruleable, Splittable

  belongs_to :category, optional: true
  belongs_to :merchant, optional: true

  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings

  accepts_nested_attributes_for :taggings, allow_destroy: true

  # Anexos (nota fiscal, boleto, comprovante PIX, etc.) via Active Storage.
  # Imagens (JPEG, PNG, GIF, WebP) e PDF, ate MAX_ATTACHMENT_SIZE cada.
  # Escopo por familia, gerenciados so pelo dono da familia.
  has_many_attached :attachments do |attachable|
    attachable.variant :thumbnail, resize_to_limit: [ 150, 150 ]
  end

  MAX_ATTACHMENTS_PER_TRANSACTION = 10
  MAX_ATTACHMENT_SIZE = 10.megabytes
  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg image/jpg image/png image/gif image/webp
    application/pdf
  ].freeze

  validate :validate_attachments, if: -> { attachments.attached? }

  enum :kind, {
    standard: "standard", # A regular transaction, included in budget analytics
    funds_movement: "funds_movement", # Movement of funds between accounts, excluded from budget analytics
    cc_payment: "cc_payment", # A CC payment, excluded from budget analytics (CC payments offset the sum of expense transactions)
    loan_payment: "loan_payment", # A payment to a Loan account, treated as an expense in budgets
    one_time: "one_time" # A one-time expense/income, excluded from budget analytics
  }

  # Kinds that represent one half of a Transfer pair. Recurring-pattern
  # detection skips these: grouping a single side under its account would
  # produce incoherent "patterns" that don't reflect the account-pair flow.
  TRANSFER_KINDS = %w[funds_movement cc_payment loan_payment].freeze

  # US-03 (merge manual de duplicatas de reimportacao): janela padrao, em dias,
  # dentro da qual dois lancamentos de mesma conta/valor/moeda sao tratados
  # como potencialmente duplicados. Reimportacoes de CSV/OFX costumam variar a
  # data de liquidacao em poucos dias, entao usamos uma janela pequena.
  DUPLICATE_WINDOW_DAYS = 3

  # Overarching grouping method for all transfer-type transactions
  def transfer?
    funds_movement? || cc_payment? || loan_payment?
  end

  # US-03: sugere lancamentos potencialmente duplicados deste, dentro da mesma
  # conta. Heuristica: mesma moeda + mesmo valor exato + data dentro de uma
  # janela de +/- window_days. Retorna Entries (nao Transactions) para manter a
  # UI consistente com o matcher de transferencias. Nada e mesclado aqui: apenas
  # sugere. Assim, uma colisao legitima (dois lancamentos identicos de verdade)
  # continua intacta ate uma acao explicita do usuario.
  def duplicate_candidates(window_days: DUPLICATE_WINDOW_DAYS, limit: 20, offset: 0)
    return Entry.none unless entry.present? && entry.date.present?

    account = entry.account
    window_start = entry.date - window_days
    window_end = entry.date + window_days

    scope = account.entries
      .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
      .where.not(id: entry.id)
      .where(currency: entry.currency)
      .where(amount: entry.amount)
      .where(date: window_start..window_end)

    # Reconciliacao com a Onda 1 (split de transacao): pais de split nao sao
    # lancamentos reais e nao devem aparecer como candidatos a duplicata. O
    # scope `excluding_split_parents` ja existe apos a integracao da Onda 1,
    # entao filtramos os pais de split automaticamente.
    if Transaction.respond_to?(:excluding_split_parents)
      real_transaction_ids = Transaction.excluding_split_parents.select(:id)
      scope = scope.where("transactions.id IN (?)", real_transaction_ids)
    end

    scope
      .order(date: :desc, created_at: :desc)
      .limit(limit)
      .offset(offset)
  end

  # US-03: mescla o lancamento duplicado `duplicate_entry` neste (que sobrevive).
  # O sobrevivente mantem seus proprios dados; onde ele estiver vazio, herda os
  # do duplicado (categoria, estabelecimento, observacoes, exclusao e etiquetas).
  # Depois destroi o Entry duplicado. Retorna true em caso de sucesso.
  #
  # Seguranca: recusa mesclar consigo mesmo, entre contas diferentes, ou quando
  # o duplicado faz parte de uma transferencia (destruir um lado quebraria o par).
  def merge_duplicate!(duplicate_entry)
    survivor_entry = entry
    return false unless survivor_entry.present?
    return false unless duplicate_entry.is_a?(Entry)
    return false if duplicate_entry.id == survivor_entry.id

    duplicate_transaction = duplicate_entry.entryable
    return false unless duplicate_transaction.is_a?(Transaction)
    return false if duplicate_entry.account_id != survivor_entry.account_id
    return false if transfer? || duplicate_transaction.transfer?

    ApplicationRecord.transaction do
      # Locks de linha evitam merges concorrentes sobre o mesmo par.
      survivor_entry.lock!
      duplicate_entry.lock!

      survivor_attrs = {}
      survivor_attrs[:category_id] = duplicate_transaction.category_id if category_id.blank? && duplicate_transaction.category_id.present?
      survivor_attrs[:merchant_id] = duplicate_transaction.merchant_id if merchant_id.blank? && duplicate_transaction.merchant_id.present?

      # Etiquetas: uniao das duas transacoes.
      merged_tag_ids = (tag_ids + duplicate_transaction.tag_ids).uniq
      survivor_attrs[:tag_ids] = merged_tag_ids if merged_tag_ids.sort != tag_ids.sort

      update!(survivor_attrs) if survivor_attrs.any?

      entry_attrs = {}
      entry_attrs[:notes] = duplicate_entry.notes if survivor_entry.notes.blank? && duplicate_entry.notes.present?
      entry_attrs[:excluded] = true if duplicate_entry.excluded? && !survivor_entry.excluded?
      survivor_entry.update!(entry_attrs) if entry_attrs.any?

      duplicate_entry.destroy!
    end

    survivor_entry.sync_account_later
    true
  end

  def set_category!(category)
    if category.is_a?(String)
      category = entry.account.family.categories.find_or_create_by!(
        name: category
      )
    end

    update!(category: category)
  end

  private
    def validate_attachments
      if attachments.size > MAX_ATTACHMENTS_PER_TRANSACTION
        errors.add(:attachments, :too_many, max: MAX_ATTACHMENTS_PER_TRANSACTION)
      end

      attachments.each_with_index do |attachment, index|
        if attachment.byte_size > MAX_ATTACHMENT_SIZE
          errors.add(:attachments, :too_large, index: index + 1, max_mb: MAX_ATTACHMENT_SIZE / 1.megabyte)
        end

        unless ALLOWED_CONTENT_TYPES.include?(attachment.content_type)
          errors.add(:attachments, :invalid_format, index: index + 1, file_format: attachment.content_type)
        end
      end
    end
end
