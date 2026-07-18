require "test_helper"

class LoansControllerTest < ActionDispatch::IntegrationTest
  include AccountableResourceInterfaceTest

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:loan)
  end

  test "creates with loan details" do
    assert_difference -> { Account.count } => 1,
      -> { Loan.count } => 1,
      -> { Valuation.count } => 1,
      -> { Entry.count } => 1 do
      post loans_path, params: {
        account: {
          name: "New Loan",
          balance: 50000,
          currency: "USD",
          accountable_type: "Loan",
          accountable_attributes: {
            interest_rate: 5.5,
            term_months: 60,
            rate_type: "fixed",
            initial_balance: 50000
          }
        }
      }
    end

    created_account = Account.order(:created_at).last

    assert_equal "New Loan", created_account.name
    assert_equal 50000, created_account.balance
    assert_equal "USD", created_account.currency
    assert_equal 5.5, created_account.accountable.interest_rate
    assert_equal 60, created_account.accountable.term_months
    assert_equal "fixed", created_account.accountable.rate_type
    assert_equal 50000, created_account.accountable.initial_balance

    assert_redirected_to created_account
    # Mensagem traduzida (default_locale = pt-BR): resolve pela mesma chave do controller
    assert_equal I18n.t("accounts.create.success", type: "Loan"), flash[:notice]
    assert_enqueued_with(job: SyncJob)
  end

  test "honors a same-site relative return_to after create" do
    post loans_path, params: {
      account: {
        name: "Return To Loan",
        balance: 1000,
        currency: "USD",
        accountable_type: "Loan",
        return_to: "/accounts",
        accountable_attributes: { rate_type: "fixed" }
      }
    }

    assert_redirected_to "/accounts"
  end

  test "ignores an off-site return_to and falls back to the account" do
    [ "https://evil.com", "//evil.com", "/\\evil.com", "javascript:alert(1)" ].each do |malicious|
      post loans_path, params: {
        account: {
          name: "Malicious Return Loan",
          balance: 1000,
          currency: "USD",
          accountable_type: "Loan",
          return_to: malicious,
          accountable_attributes: { rate_type: "fixed" }
        }
      }

      created_account = Account.order(:created_at).last
      assert_redirected_to created_account, "expected fallback redirect for return_to=#{malicious.inspect}"
    end
  end

  test "updates with loan details" do
    assert_no_difference [ "Account.count", "Loan.count" ] do
      patch loan_path(@account), params: {
        account: {
          name: "Updated Loan",
          balance: 45000,
          currency: "USD",
          accountable_type: "Loan",
          accountable_attributes: {
            id: @account.accountable_id,
            interest_rate: 4.5,
            term_months: 48,
            rate_type: "fixed",
            initial_balance: 48000
          }
        }
      }
    end

    @account.reload

    assert_equal "Updated Loan", @account.name
    assert_equal 45000, @account.balance
    assert_equal 4.5, @account.accountable.interest_rate
    assert_equal 48, @account.accountable.term_months
    assert_equal "fixed", @account.accountable.rate_type
    assert_equal 48000, @account.accountable.initial_balance

    assert_redirected_to @account
    assert_equal I18n.t("accounts.update.success", type: "Loan"), flash[:notice]
    assert_enqueued_with(job: SyncJob)
  end
end
