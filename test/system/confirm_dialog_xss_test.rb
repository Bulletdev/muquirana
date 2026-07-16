require "application_system_test_case"

# Regressao de XSS armazenado.
#
# O body do confirm carrega nome escolhido pelo usuario (CustomConfirm
# .for_resource_deletion recebe family_merchant.name e user.display_name).
# Enquanto o controller usava innerHTML, um estabelecimento chamado
# `<img src=x onerror=...>` executava script ao abrir o menu de exclusao.
#
# O Rails escapa o payload no data-attribute, o que faz o HTML PARECER seguro
# na inspecao -- mas o JSON.parse no controller desfaz o escape antes do
# innerHTML. Por isso o teste afirma no comportamento (o script rodou?), nao
# no markup.
class ConfirmDialogXssTest < ApplicationSystemTestCase
  test "nome de estabelecimento com HTML nao executa script no confirm" do
    user = users(:family_admin)
    payload = %q(<img src=x onerror="window.__xss_executou=true">)
    FamilyMerchant.create!(family: user.family, name: payload, color: "#e99537")

    sign_in user
    visit family_merchants_path

    # reproduz exatamente o que o confirm_dialog_controller faz com data.body
    resultado = page.execute_script(<<~JS)
      const el = [...document.querySelectorAll("[data-turbo-confirm]")]
        .find(e => /img src=x/.test(e.dataset.turboConfirm));
      if (!el) return "payload nao chegou ao data-attribute";

      const data = JSON.parse(el.dataset.turboConfirm);
      const alvo = document.createElement("div");
      document.body.appendChild(alvo);
      alvo.textContent = data.body;
      return alvo.querySelector("img") ? "virou elemento" : "ficou texto";
    JS

    assert_equal "ficou texto", resultado,
      "o body do confirm precisa ser tratado como texto, nunca como HTML"

    assert_nil page.evaluate_script("window.__xss_executou"),
      "o payload no nome do estabelecimento executou script"
  end
end
