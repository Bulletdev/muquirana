# O nome que o usuario ve para um lancamento de saldo ("Saldo inicial",
# "Atualizacao manual de saldo"...). Eram 12 literais em ingles, que apareciam
# na tela de conta mesmo com a app inteira em portugues.
#
# A chave e por GRUPO de tipo de conta porque o conceito muda com ele: para um
# imovel o saldo inicial e o "preco de compra"; para um emprestimo, o "saldo
# devedor original". Nao e a mesma frase traduzida seis vezes.
class Valuation::Name
  def initialize(valuation_kind, accountable_type)
    @valuation_kind = valuation_kind
    @accountable_type = accountable_type
  end

  def to_s
    case valuation_kind
    when "opening_anchor"
      opening_anchor_name
    when "current_anchor"
      current_anchor_name
    else
      recon_name
    end
  end

  private
    attr_reader :valuation_kind, :accountable_type

    # `default` cobre Depository, CreditCard, OtherLiability e qualquer tipo
    # novo -- assim um accountable adicionado depois nasce com nome traduzido
    # em vez de estourar I18n::MissingTranslation.
    def grupo
      case accountable_type
      when "Property", "Vehicle" then "asset"
      when "Loan" then "loan"
      when "Investment", "Crypto", "OtherAsset" then "account_value"
      else "default"
      end
    end

    def opening_anchor_name
      I18n.t("valuations.names.opening_anchor.#{grupo}")
    end

    def current_anchor_name
      I18n.t("valuations.names.current_anchor.#{grupo}")
    end

    # A reconciliacao agrupa diferente do resto: imovel, veiculo, investimento,
    # cripto e outros ativos dizem todos "atualizacao manual de valor". Só
    # emprestimo e as contas de saldo se distinguem.
    def recon_name
      chave = case grupo
      when "loan" then "loan"
      when "default" then "default"
      else "value"
      end

      I18n.t("valuations.names.recon.#{chave}")
    end
end
