require "test_helper"

# Export CSV de transacoes da familia (Onda 1), pela UI (sessao) e por API key
# (integracao tipo Google Sheets), respeitando o escopo de leitura.
#
# Classe separada de ReportsControllerTest (dashboard, US-10) de proposito: o
# dashboard loga o usuario no setup, enquanto os testes de export precisam
# exercitar tambem o fluxo NAO autenticado -- setups incompativeis no mesmo
# arquivo. Ambas as classes batem no mesmo ReportsController.
class ReportsExportTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @family = @user.family

    # Transacao conhecida para conferir que aparece no CSV.
    @entry = create_transaction(
      account: accounts(:depository),
      name: "Cafe da manha",
      date: Date.new(2026, 7, 1),
      amount: 42.50,
      currency: "USD"
    )
  end

  # ----- UI (sessao) -----

  test "logged in user exports transactions as CSV" do
    sign_in @user

    get export_transactions_report_url(format: :csv)

    assert_response :success
    assert_match(/text\/csv/, response.media_type)
    assert_includes response.headers["Content-Disposition"].to_s, "attachment"
    assert_includes response.body, "Cafe da manha"
    # Cabecalho localizado (locale default da familia).
    assert_match(/Descrição|Description/, response.body.lines.first)
  end

  test "unauthenticated request without api key is redirected to login" do
    get export_transactions_report_url(format: :csv)

    assert_response :redirect
    assert_redirected_to new_session_url
  end

  # ----- API key (header) -----

  test "exports via api key in header with read scope" do
    api_key = create_api_key(scopes: [ "read" ])

    get export_transactions_report_url(format: :csv),
        headers: { "X-Api-Key" => api_key.display_key }

    assert_response :success
    assert_match(/text\/csv/, response.media_type)
    assert_includes response.body, "Cafe da manha"
  end

  # ----- API key (query param, estilo Google Sheets IMPORTDATA) -----

  test "exports via api key in query param" do
    api_key = create_api_key(scopes: [ "read_write" ])

    get export_transactions_report_url(format: :csv, api_key: api_key.display_key)

    assert_response :success
    assert_includes response.body, "Cafe da manha"
  end

  # ----- Auth negativa -----

  test "rejects invalid api key" do
    get export_transactions_report_url(format: :csv), headers: { "X-Api-Key" => "nope" }

    assert_response :unauthorized
  end

  test "rejects revoked api key" do
    api_key = create_api_key(scopes: [ "read" ])
    api_key.revoke!

    get export_transactions_report_url(format: :csv),
        headers: { "X-Api-Key" => api_key.display_key }

    assert_response :unauthorized
  end

  test "rejects api key without read scope" do
    # Escopo sem leitura precisa contornar a validacao do modelo (que so aceita
    # read/read_write) para exercitar o gate de escopo do controller.
    api_key = ApiKey.new(
      user: @user,
      name: "Write only",
      display_key: "write_only_#{SecureRandom.hex(8)}",
      scopes: [ "write" ]
    )
    api_key.save!(validate: false)

    get export_transactions_report_url(format: :csv),
        headers: { "X-Api-Key" => api_key.display_key }

    assert_response :forbidden
  end

  # ----- Filtro de periodo -----

  test "respects period filter" do
    sign_in @user

    old_entry = create_transaction(
      account: accounts(:depository),
      name: "Compra antiga",
      date: Date.new(2020, 1, 1),
      amount: 10,
      currency: "USD"
    )

    get export_transactions_report_url(
      format: :csv,
      q: { start_date: "2026-06-01", end_date: "2026-07-31" }
    )

    assert_response :success
    assert_includes response.body, "Cafe da manha"
    assert_not_includes response.body, "Compra antiga"
  end

  private
    def create_api_key(scopes:)
      @user.api_keys.destroy_all
      ApiKey.create!(
        user: @user,
        name: "Export key #{SecureRandom.hex(4)}",
        display_key: "export_test_#{SecureRandom.hex(8)}",
        scopes: scopes
      )
    end
end
