# Parses OFX (Open Financial Exchange) bank/credit-card statements.
#
# OFX e o formato de extrato mais comum exportado pelos bancos brasileiros
# (Itau, Bradesco, Banco do Brasil, Santander, Nubank, Caixa). Ele existe em
# duas formas:
#
#   - OFX 1.x (SGML): cabecalho "key:value", elementos de dado SEM tag de
#     fechamento (ex.: "<TRNAMT>-50.00"). Agregados (STMTTRN, BANKTRANLIST, ...)
#     TEM fechamento ("</STMTTRN>"). E a forma mais comum nos bancos BR.
#   - OFX 2.x (XML): cabecalho XML, todos os elementos fechados
#     (ex.: "<TRNAMT>-50.00</TRNAMT>").
#
# Este parser trata as DUAS formas com a mesma logica: para um elemento de dado
# capturamos tudo depois da tag ate o proximo "<" ou quebra de linha - o que
# funciona tanto para "<TRNAMT>-50.00\n" (SGML) quanto para
# "<TRNAMT>-50.00</TRNAMT>" (XML). Agregados usam sempre tag de fechamento nas
# duas formas.
#
# Campos extraidos por transacao (<STMTTRN>):
#   TRNTYPE   tipo (DEBIT, CREDIT, ...)
#   DTPOSTED  data (YYYYMMDD[HHMMSS][tz]) - usamos os 8 primeiros digitos
#   TRNAMT    valor com sinal (negativo = saida)
#   FITID     id unico da transacao no banco (chave de deduplicacao)
#   NAME      contraparte / historico curto
#   MEMO      descricao / historico longo
#   CHECKNUM  numero do documento (opcional)
#
# Saldo (<LEDGERBAL>): BALAMT (valor) e DTASOF (data de referencia).
# Conta (<BANKACCTFROM> / <CCACCTFROM>): BANKID, ACCTID, ACCTTYPE.
module OfxParser
  ParsedTransaction = Struct.new(
    :date, :amount, :name, :memo, :fitid, :trntype, :check_num,
    keyword_init: true
  )

  ParsedBalance = Struct.new(:amount, :date, keyword_init: true)
  ParsedAccount = Struct.new(:bank_id, :account_id, :account_type, keyword_init: true)

  # ------------------------------------------------------------------
  # API publica
  # ------------------------------------------------------------------

  # Transcodifica os bytes do arquivo para UTF-8. Bancos BR costumam exportar
  # OFX em Windows-1252 (Latin-1); tentamos UTF-8 primeiro e caimos para
  # Windows-1252 preservando os acentos.
  def self.normalize_encoding(content)
    return content if content.nil?

    binary = content.b

    utf8_attempt = binary.dup.force_encoding("UTF-8")
    return utf8_attempt if utf8_attempt.valid_encoding?

    binary.encode("UTF-8", "Windows-1252", invalid: :replace, undef: :replace, replace: "")
  end

  # Verdadeiro quando o conteudo parece um arquivo OFX valido.
  def self.valid?(content)
    return false if content.blank?

    binary = content.b
    binary.include?("<OFX>") || binary.match?(/OFXHEADER[:=]/i)
  end

  # Parseia todas as transacoes do extrato. Retorna um array de
  # ParsedTransaction (data ja em ISO 8601).
  def self.parse(content)
    return [] unless valid?(content)

    content = normalize_encoding(content)
    body    = strip_header(content)

    body.scan(/<STMTTRN>(.*?)<\/STMTTRN>/mi).filter_map do |captures|
      build_transaction(captures.first)
    end
  end

  # Retorna o saldo do extrato (<LEDGERBAL>) como ParsedBalance, ou nil.
  def self.parse_balance(content)
    return nil unless valid?(content)

    content = normalize_encoding(content)
    body    = strip_header(content)

    block = body.match(/<LEDGERBAL>(.*?)<\/LEDGERBAL>/mi)&.captures&.first
    return nil unless block

    amount = parse_amount(field(block, "BALAMT"))
    return nil if amount.nil?

    date = parse_date(field(block, "DTASOF"))

    ParsedBalance.new(amount: amount.to_d, date: date.present? ? Date.parse(date) : nil)
  end

  # Retorna os dados da conta (<BANKACCTFROM> ou <CCACCTFROM>) como
  # ParsedAccount, ou nil.
  def self.parse_account(content)
    return nil unless valid?(content)

    content = normalize_encoding(content)
    body    = strip_header(content)

    block = body.match(/<BANKACCTFROM>(.*?)<\/BANKACCTFROM>/mi)&.captures&.first ||
            body.match(/<CCACCTFROM>(.*?)<\/CCACCTFROM>/mi)&.captures&.first
    return nil unless block

    ParsedAccount.new(
      bank_id:      field(block, "BANKID"),
      account_id:   field(block, "ACCTID"),
      account_type: field(block, "ACCTTYPE")
    )
  end

  # Datas cruas (DTPOSTED) para deteccao/preview - sempre YYYYMMDD apos limpeza.
  def self.extract_raw_dates(content)
    return [] unless valid?(content)

    content = normalize_encoding(content)
    body    = strip_header(content)

    body.scan(/<DTPOSTED>([^<\r\n]*)/i).flatten.filter_map { |raw| clean_date(raw) }
  end

  # ------------------------------------------------------------------
  # Helpers privados
  # ------------------------------------------------------------------

  # Remove o cabecalho OFX (linhas "key:value" do SGML ou o prologo XML) e
  # devolve so o corpo a partir de <OFX>.
  def self.strip_header(content)
    idx = content.index(/<OFX>/i)
    idx ? content[idx..] : content
  end
  private_class_method :strip_header

  # Le um elemento de dado de dentro de um bloco: captura tudo depois de <TAG>
  # ate o proximo "<" ou quebra de linha. Funciona para SGML e XML.
  def self.field(block, tag)
    match = block.match(/<#{tag}>([^<\r\n]*)/i)
    return nil unless match

    value = match[1].to_s.strip
    value = unescape(value)
    value.presence
  end
  private_class_method :field

  def self.unescape(str)
    str.gsub("&amp;", "&")
       .gsub("&lt;", "<")
       .gsub("&gt;", ">")
       .gsub("&quot;", '"')
       .gsub("&apos;", "'")
  end
  private_class_method :unescape

  def self.build_transaction(block)
    raw_date   = field(block, "DTPOSTED")
    raw_amount = field(block, "TRNAMT")

    date   = parse_date(raw_date)
    amount = parse_amount(raw_amount)

    return nil unless date && amount

    name = field(block, "NAME")
    memo = field(block, "MEMO")

    OfxParser::ParsedTransaction.new(
      date:      date,
      amount:    amount,
      name:      name,
      memo:      memo,
      fitid:     field(block, "FITID"),
      trntype:   field(block, "TRNTYPE"),
      check_num: field(block, "CHECKNUM")
    )
  end
  private_class_method :build_transaction

  # Extrai os 8 digitos YYYYMMDD do inicio de uma data OFX, ignorando hora e
  # fuso (ex.: "20240115120000[-3:BRT]").
  def self.clean_date(raw)
    return nil if raw.blank?

    digits = raw.gsub(/\D/, "")
    return nil if digits.length < 8

    digits[0, 8]
  end
  private_class_method :clean_date

  # Converte a data OFX para ISO 8601 (YYYY-MM-DD), ou nil se invalida.
  def self.parse_date(raw)
    cleaned = clean_date(raw)
    return nil unless cleaned

    Date.strptime(cleaned, "%Y%m%d").iso8601
  rescue Date::Error, ArgumentError
    nil
  end
  private_class_method :parse_date

  # Normaliza um valor OFX para string decimal limpa. Trata tanto ponto quanto
  # virgula como separador decimal (alguns bancos BR exportam "-50,00").
  def self.parse_amount(raw)
    return nil if raw.blank?

    s = raw.strip

    if s.include?(",") && !s.include?(".")
      # Virgula decimal: "-1.234,56" -> remove pontos de milhar, virgula vira ponto
      s = s.delete(".").tr(",", ".")
    else
      # Ponto decimal: remove virgulas de milhar
      s = s.delete(",")
    end

    s =~ /\A-?\d+\.?\d*\z/ ? s : nil
  end
  private_class_method :parse_amount
end
