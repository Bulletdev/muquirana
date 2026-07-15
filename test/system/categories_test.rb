require "application_system_test_case"

# Nada de rotulo de UI fixo em ingles aqui.
#
# O default_locale do app e :"pt-BR" e as familias nascem com locale "pt-BR"
# (Localize#switch_locale resolve pelo Current.family). Textos que o Rails
# traduz sozinho -- rotulo de submit (helpers.submit.*), nome de model, nome de
# atributo, mensagem de validacao -- ja saem em portugues, antes mesmo de a
# traducao das strings da aplicacao comecar. Ex: o botao virou "Criar Category".
#
# Resolver cada rotulo pelo I18n mantem o teste valido em qualquer locale e
# sobrevive a traducao incremental, em vez de quebrar a cada string movida.
class CategoriesTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
  end

  test "can create category" do
    visit categories_url
    click_link I18n.t("categories.new.new_category")
    # O rotulo do campo vem da view (`label: t(".name_label")` em
    # categories/_form), nao de Category.human_attribute_name -- que nao tem
    # traducao e cairia no humanize ("Name").
    fill_in I18n.t("categories.form.name_label"), with: "My Shiny New Category"
    click_button I18n.t("helpers.submit.create", model: Category.model_name.human)

    visit categories_url
    assert_text "My Shiny New Category"
  end

  test "trying to create a duplicate category fails" do
    visit categories_url
    click_link I18n.t("categories.new.new_category")
    fill_in I18n.t("categories.form.name_label"), with: categories(:food_and_drink).name
    click_button I18n.t("helpers.submit.create", model: Category.model_name.human)

    assert_text "#{Category.human_attribute_name(:name)} #{I18n.t('errors.messages.taken')}"
  end
end
