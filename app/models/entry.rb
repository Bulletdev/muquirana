class Entry < ApplicationRecord
  include Monetizable, Enrichable

  monetize :amount

  belongs_to :account
  belongs_to :transfer, optional: true
  belongs_to :import, optional: true

  delegated_type :entryable, types: Entryable::TYPES, dependent: :destroy
  accepts_nested_attributes_for :entryable

  validates :date, :name, :amount, :currency, presence: true
  validates :date, uniqueness: { scope: [ :account_id, :entryable_type ] }, if: -> { valuation? }
  validates :date, comparison: { greater_than: -> { min_supported_date } }
  validate :entryable_associations_belong_to_family

  scope :visible, -> {
    joins(:account).where(accounts: { status: [ "draft", "active" ] })
  }

  scope :chronological, -> {
    order(
      date: :asc,
      Arel.sql("CASE WHEN entries.entryable_type = 'Valuation' THEN 1 ELSE 0 END") => :asc,
      created_at: :asc
    )
  }

  scope :reverse_chronological, -> {
    order(
      date: :desc,
      Arel.sql("CASE WHEN entries.entryable_type = 'Valuation' THEN 1 ELSE 0 END") => :desc,
      created_at: :desc
    )
  }

  def classification
    amount.negative? ? "income" : "expense"
  end

  def lock_saved_attributes!
    super
    entryable.lock_saved_attributes!
  end

  def sync_account_later
    sync_start_date = [ date_previously_was, date ].compact.min unless destroyed?
    account.sync_later(window_start_date: sync_start_date)
  end

  def entryable_name_short
    entryable_type.demodulize.underscore
  end

  def balance_trend(entries, balances)
    Balance::TrendCalculator.new(self, entries, balances).trend
  end

  def linked?
    plaid_id.present?
  end

  class << self
    def search(params)
      EntrySearch.new(params).build_query(all)
    end

    # arbitrary cutoff date to avoid expensive sync operations
    def min_supported_date
      30.years.ago.to_date
    end

    def bulk_update!(bulk_update_params)
      bulk_attributes = {
        date: bulk_update_params[:date],
        notes: bulk_update_params[:notes],
        entryable_attributes: {
          category_id: bulk_update_params[:category_id],
          merchant_id: bulk_update_params[:merchant_id],
          tag_ids: bulk_update_params[:tag_ids]
        }.compact_blank
      }.compact_blank

      return 0 if bulk_attributes.blank?

      transaction do
        all.each do |entry|
          bulk_attributes[:entryable_attributes][:id] = entry.entryable_id if bulk_attributes[:entryable_attributes].present?
          entry.update! bulk_attributes

          entry.lock_saved_attributes!
          entry.entryable.lock_attr!(:tag_ids) if entry.transaction? && entry.transaction.tags.any?
        end
      end

      all.size
    end
  end

  private
    # Isolamento multi-tenant nas FKs de Transaction.
    #
    # Nao ha default_scope de tenant nem Pundit neste app: o isolamento existe
    # apenas enquanto a query parte de Current.family. Isso protege o `find` --
    # e nao protege o `update`. category_id / merchant_id / tag_ids chegam de
    # params e sao atribuidos a uma entry da propria familia sem que nada
    # verifique se o alvo da FK pertence a ela.
    #
    # Sem esta validacao, POST /api/v1/transactions com o category_id de outra
    # familia retorna 201 e o jbuilder devolve nome/cor/classificacao daquela
    # categoria no corpo da resposta -- um oraculo de leitura cross-family por
    # enumeracao de UUID, alem de poluir a FK dos dois lados.
    #
    # A validacao mora no Entry, e nao no Transaction, porque:
    #   1. Entry conhece a account, logo a familia. Transaction so alcanca a
    #      familia via `entry`, que e has_one polimorfica (`as: :entryable`) --
    #      o Rails nao infere inverse_of em polimorfica, entao `entry` seria nil
    #      durante a validacao de um registro novo.
    #   2. Todos os caminhos de escrita convergem aqui com entryable_attributes:
    #      API create/update, web create/update, Entry.bulk_update! e transfers.
    #      Uma validacao cobre os cinco; no controller cobriria um.
    def entryable_associations_belong_to_family
      return unless transaction?
      return if account.nil?

      txn = entryable
      return if txn.nil?

      family_id = account.family_id

      if txn.category_id.present? && !Category.exists?(id: txn.category_id, family_id: family_id)
        errors.add(:base, "Category must belong to the same family as the account")
      end

      # ProviderMerchant (Plaid/Synth/AI) e global por design e nao tem
      # family_id -- e compartilhado entre familias de proposito. Apenas
      # FamilyMerchant e escopado, entao so ele e verificado.
      if txn.merchant_id.present? &&
         FamilyMerchant.where(id: txn.merchant_id).where.not(family_id: family_id).exists?
        errors.add(:base, "Merchant must belong to the same family as the account")
      end

      tag_ids = txn.tags.map(&:id).compact
      if tag_ids.any? && Tag.where(id: tag_ids).where.not(family_id: family_id).exists?
        errors.add(:base, "Tags must belong to the same family as the account")
      end
    end
end
