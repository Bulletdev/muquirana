# Coracao da escrita da fundacao generica de providers (portado/adaptado do Sure).
#
# Todo provider de conta (hoje o Plaid; amanha outros) importa transacoes por
# aqui, ganhando de graca a regra de dedup CROSS-source decidida pelo dono do
# produto -- "manual/CSV vence":
#
#   1. Campo travado pelo usuario -> o provider NUNCA sobrescreve (o enrich ja
#      respeita `locked_attributes`).
#   2. Campo vazio -> o provider PREENCHE o que o usuario nao definiu (complementa,
#      nao sobrescreve).
#   3. Chave de match = data + valor + conta -> reivindica UM lancamento manual
#      correspondente, mas nunca funde dois lancamentos legitimos identicos: ao
#      reivindicar, gravamos external_id no manual, de modo que uma segunda
#      transacao identica do provider nao ache mais nenhum manual "livre" e crie
#      a propria entry.
#
# Diferente do Sure (que carrega holdings/trades/pending/goals/investment), esta
# versao e enxuta e casa com o modelo de Entry/Transaction do Muquirana.
class Account::ProviderImportAdapter
  attr_reader :account

  def initialize(account)
    @account = account
  end

  # Importa (cria ou atualiza) uma transacao vinda de um provider.
  #
  # @param external_id [String] id unico da transacao no provider
  # @param source [String] nome do provider (ex.: "plaid")
  # @param amount [Numeric] valor
  # @param currency [String] moeda (ex.: "USD")
  # @param date [Date, String] data
  # @param name [String] descricao
  # @param category_id [String, nil] categoria opcional (enriquecida)
  # @param merchant [Merchant, nil] merchant opcional (enriquecido)
  # @param notes [String, nil] notas opcionais (enriquecidas)
  # @return [Entry] a entry criada ou atualizada
  def import_transaction(external_id:, source:, amount:, currency:, date:, name:, category_id: nil, merchant: nil, notes: nil)
    raise ArgumentError, "external_id is required" if external_id.blank?
    raise ArgumentError, "source is required" if source.blank?

    date = date.is_a?(Date) ? date : Date.parse(date.to_s)

    Account.transaction do
      # Chave do provider = (external_id, source). Permite que providers distintos
      # sincronizem a mesma conta com entries separadas.
      entry = account.entries.find_or_initialize_by(external_id: external_id, source: source) do |e|
        e.entryable = Transaction.new
      end

      # Guarda contra colisao de tipo: mesmo external_id ja usado por outro
      # entryable (Trade/Valuation) e erro.
      if entry.persisted? && !entry.entryable.is_a?(Transaction)
        raise ArgumentError, "Entry with external_id '#{external_id}' already exists with different entryable type: #{entry.entryable_type}"
      end

      # DEDUP CROSS-SOURCE (ponto 3): quando a transacao do provider e nova,
      # tenta reivindicar um lancamento MANUAL correspondente (mesma data+valor+
      # moeda, sem external_id). Reivindicar != fundir: gravamos external_id no
      # manual para que uma segunda transacao identica do provider nao o ache de
      # novo e crie a propria entry.
      if entry.new_record?
        duplicate = find_duplicate_transaction(date: date, amount: amount, currency: currency)
        if duplicate
          entry = duplicate
          entry.assign_attributes(external_id: external_id, source: source)
        end
      end

      # data/valor/moeda sao a propria chave de match -- num manual reivindicado ja
      # sao iguais; numa entry nova, sao os fatos do provider.
      entry.assign_attributes(amount: amount, currency: currency, date: date)

      # enrich_attribute respeita locks do usuario (ponto 1) e so preenche o que
      # esta vazio/diferente (ponto 2). Tambem persiste a entry.
      entry.enrich_attribute(:name, name, source: source) if name.present?
      entry.enrich_attribute(:notes, notes, source: source) if notes.present?

      # Garante persistencia mesmo quando name/notes vierem em branco.
      entry.save! if entry.new_record? || entry.changed?

      if category_id.present?
        entry.transaction.enrich_attribute(:category_id, category_id, source: source)
      end

      if merchant
        entry.transaction.enrich_attribute(:merchant_id, merchant.id, source: source)
      end

      entry
    end
  end

  # Encontra um possivel duplicado vindo de entrada manual/CSV.
  # Casa por data + valor + moeda, apenas entries SEM external_id (manual/CSV) e
  # do tipo Transaction. A ordenacao por created_at garante reivindicar o mais
  # antigo primeiro.
  #
  # @return [Entry, nil]
  def find_duplicate_transaction(date:, amount:, currency:, exclude_entry_ids: nil)
    date = Date.parse(date.to_s) unless date.is_a?(Date)

    query = account.entries
                   .where(entryable_type: "Transaction")
                   .where(date: date)
                   .where(amount: amount)
                   .where(currency: currency)
                   .where(external_id: nil)

    query = query.where.not(id: exclude_entry_ids) if exclude_entry_ids.present?

    query.order(created_at: :asc).first
  end
end
