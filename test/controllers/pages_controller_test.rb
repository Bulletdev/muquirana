require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  # A demo roda em outra instancia. O botao so pode existir quando ela existe:
  # sem DEMO_URL ele tem que sumir, e nao apontar para um endereco quebrado.
  #
  # reset! porque o setup desta classe faz login, e a landing manda quem tem
  # sessao direto para o /painel -- quem ve a landing e justamente quem chega
  # deslogado.
  test "landing hides the demo button without DEMO_URL" do
    reset!

    get root_url

    assert_response :success
    assert_select "a[href=?]", "https://demo.muquirana.com", count: 0
    assert_no_match I18n.t("pages.home.cta_secondary"), response.body
  end

  test "landing shows the demo button when DEMO_URL is set" do
    reset!

    with_env_overrides DEMO_URL: "https://demo.muquirana.com" do
      get root_url

      assert_response :success
      assert_select "a[href=?]", "https://demo.muquirana.com" do |links|
        assert_equal I18n.t("pages.home.cta_secondary"), links.first.text.strip
      end
    end
  end

  setup do
    sign_in @user = users(:family_admin)
  end

  test "dashboard" do
    # O painel saiu de "/" para "/painel": "/" e a landing publica, que
    # redireciona quem tem sessao. Aponte para o painel direto.
    get dashboard_path
    assert_response :ok
  end

  # O cassette e uma resposta real da API do GitHub gravada contra
  # maybe-finance/maybe, o repositorio do projeto original. O env precisa
  # coincidir com o que foi gravado para o VCR casar a requisicao. Isso e
  # fixture de HTTP de terceiro, nao marca exibida ao usuario -- e nao ha como
  # regravar contra um repositorio que ainda nao existe.
  test "changelog" do
    ClimateControl.modify GITHUB_REPO_OWNER: "maybe-finance", GITHUB_REPO_NAME: "maybe" do
      VCR.use_cassette("git_repository_provider/fetch_latest_release_notes") do
        get changelog_path
        assert_response :ok
      end
    end
  end

  test "changelog with nil release notes" do
    # Mock the GitHub provider to return nil (simulating API failure or no releases)
    github_provider = mock
    github_provider.expects(:fetch_latest_release_notes).returns(nil)
    Provider::Registry.stubs(:get_provider).with(:github).returns(github_provider)

    get changelog_path
    assert_response :ok
    assert_select "h2", text: "Notas de versão indisponíveis"
  end

  # O estado vazio nao pode exibir a identidade de nenhum outro projeto. O
  # fallback anterior injetava o avatar, o usuario e o link de releases de
  # maybe-finance -- e o teste afirmava esse link, travando o vazamento de marca.
  test "changelog fallback does not reference the upstream project" do
    github_provider = mock
    github_provider.expects(:fetch_latest_release_notes).returns(nil)
    Provider::Registry.stubs(:get_provider).with(:github).returns(github_provider)

    get changelog_path
    assert_response :ok
    assert_no_match(/maybe-finance/i, response.body)
    assert_select "a[href*='github.com']", count: 0
  end

  # Sem GITHUB_REPO_OWNER/NAME o provider nao deve chamar a API do GitHub --
  # nem a do projeto original, nem nenhuma.
  test "github provider makes no request when repo is not configured" do
    ClimateControl.modify GITHUB_REPO_OWNER: nil, GITHUB_REPO_NAME: nil do
      Octokit.expects(:releases).never
      assert_nil Provider::Github.new.fetch_latest_release_notes
    end
  end

  test "changelog with incomplete release notes" do
    # Mock the GitHub provider to return incomplete data (missing some fields)
    github_provider = mock
    incomplete_data = {
      avatar: nil,
      username: "someuser",
      name: "Test Release",
      published_at: nil,
      body: nil
    }
    github_provider.expects(:fetch_latest_release_notes).returns(incomplete_data)
    Provider::Registry.stubs(:get_provider).with(:github).returns(github_provider)

    get changelog_path
    assert_response :ok
    assert_select "h2", text: "Test Release"
    # Should not crash even with nil values
  end
end
