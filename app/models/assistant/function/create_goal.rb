class Assistant::Function::CreateGoal < Assistant::Function
  include Assistant::Function::Writable

  class << self
    def name
      "create_goal"
    end

    def description
      <<~INSTRUCTIONS
        Cria uma meta (goal) para a familia do usuario.

        Use quando o usuario descrever um objetivo para o qual quer poupar -- ex.:
        "viagem em 4 meses de R$5000", "entrada de um carro no ano que vem",
        "reserva de emergencia de R$10 mil".

        A meta se liga a UMA conta do usuario e usa o SALDO dela como progresso.
        Antes de chamar, confirme os detalhes parafraseando para o usuario: nome, valor
        alvo, data-alvo (se houver) e qual conta vai financiar. So chame apos ele confirmar.

        Restricoes:
        - A conta precisa pertencer a familia do usuario. Use o nome exatamente como
          aparece na lista de contas do usuario (get_accounts).
        - A moeda da meta e a moeda da conta ligada.
        - A data-alvo, se informada, nao pode estar no passado.

        Guard-rail: esta funcao so grava quando confirmed=true. Sem confirmacao, retorna
        apenas uma previa (requires_confirmation) para voce mostrar ao usuario.

        Em sucesso, retorna a URL da nova meta. Em falha branda (ex.: nome da conta nao
        bate), a resposta inclui a lista de contas disponiveis para voce reperguntar.
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: %w[name target_amount account_name],
      properties: {
        name: {
          type: "string",
          description: "Nome curto da meta, ex.: 'Viagem para a Italia'."
        },
        target_amount: {
          type: "number",
          description: "Valor total a poupar, na moeda da conta ligada."
        },
        account_name: {
          type: "string",
          description: "Nome da conta do usuario a ligar. Use exatamente como aparece na lista de contas. O saldo dessa conta e o progresso da meta."
        },
        target_date: {
          type: "string",
          description: "Data-alvo opcional no formato ISO 8601 (YYYY-MM-DD). Nao pode estar no passado."
        },
        notes: {
          type: "string",
          description: "Observacoes livres (opcional)."
        }
      }.merge(confirmation_property)
    )
  end

  def call(params = {})
    name = params["name"].to_s.strip
    target_amount = parse_decimal(params["target_amount"])
    target_date = parse_date(params["target_date"])
    account_name = params["account_name"].to_s.strip
    notes = params["notes"].to_s.strip

    return error("name_required", "Informe um nome para a meta.") if name.blank?
    return error("target_amount_invalid", "O valor alvo deve ser maior que zero.") unless target_amount && target_amount > 0

    if account_name.blank?
      return error("account_required", "Informe a conta a ligar a esta meta.", available_accounts: account_payload)
    end

    matches = family.accounts.visible.where(name: account_name).to_a
    if matches.empty?
      return error(
        "unknown_account",
        "A conta '#{account_name}' nao foi encontrada entre as contas do usuario.",
        available_accounts: account_payload
      )
    end

    # Contas podem repetir nome. Nao ligamos "qualquer uma" em silencio: pedimos
    # desambiguacao para o assistente reperguntar.
    if matches.size > 1
      return error(
        "ambiguous_account",
        "Mais de uma conta tem o nome '#{account_name}'. Pergunte ao usuario qual usar.",
        available_accounts: account_payload
      )
    end

    account = matches.first

    goal = family.goals.new(
      name: name,
      target_amount: target_amount,
      target_date: target_date,
      currency: account.currency,
      notes: notes.presence,
      color: Goal::COLORS.sample,
      account: account
    )
    return error("validation_failed", goal.errors.full_messages.join("; ")) unless goal.valid?

    unless confirmed?(params)
      return needs_confirmation(
        action: "create_goal",
        preview: {
          name: goal.name,
          target_amount_formatted: goal.target_amount_money.format,
          currency: goal.currency,
          target_date: goal.target_date&.iso8601,
          account_name: account.name
        },
        message: "Confirmar criacao da meta '#{goal.name}' (alvo #{goal.target_amount_money.format}) ligada a conta '#{account.name}'?"
      )
    end

    goal.save!

    {
      success: true,
      goal_id: goal.id,
      name: goal.name,
      target_amount_formatted: goal.target_amount_money.format,
      currency: goal.currency,
      target_date: goal.target_date&.iso8601,
      account_name: account.name,
      url: absolute_url_for(goal),
      message: "Meta '#{goal.name}' criada (alvo #{goal.target_amount_money.format}). Veja em #{absolute_url_for(goal)}."
    }
  rescue ActiveRecord::RecordInvalid => e
    error("validation_failed", e.record.errors.full_messages.join("; "))
  end

  private
    # URL absoluta para clientes de chat (que renderizam fora da request que
    # criou a meta). Cai para o path relativo quando nao ha host configurado.
    def absolute_url_for(goal)
      host_opts = Rails.application.config.action_mailer.default_url_options || {}
      if host_opts[:host].present?
        Rails.application.routes.url_helpers.goal_url(goal, host_opts)
      else
        Rails.application.routes.url_helpers.goal_path(goal)
      end
    end

    def parse_decimal(value)
      return nil if value.nil?
      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def parse_date(value)
      return nil if value.blank?
      Date.iso8601(value.to_s)
    rescue Date::Error, ArgumentError
      nil
    end

    def account_payload
      family.accounts.visible.pluck(:name, :currency).map { |n, c| { name: n, currency: c } }
    end
end
