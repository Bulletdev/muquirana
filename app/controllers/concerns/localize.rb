module Localize
  extend ActiveSupport::Concern

  # Idiomas oferecidos a quem ainda nao tem conta.
  #
  # NAO e I18n.available_locales de proposito. Aquela lista inclui :es, que
  # existe no config mas nao esta traduzido (mais de 1700 chaves faltando, a
  # tela sai em ingles). Oferecer um idioma que nao existe e pior do que nao
  # oferecer nenhum. Quando o es for traduzido, entra aqui.
  VISITOR_LOCALES = [ :"pt-BR", :en ].freeze

  included do
    around_action :switch_locale
    around_action :switch_timezone
    helper_method :visitor_locale
  end

  private
    # Ordem: preferencia da familia > escolha do visitante > default.
    #
    # A familia vem primeiro porque quem tem conta ja disse qual idioma quer,
    # numa tela de configuracao -- isso nao pode ser atropelado por um ?locale
    # em um link clicado sem querer.
    #
    # Antes era so `Current.family.try(:locale) || I18n.default_locale`: quem
    # nao tinha conta caia SEMPRE em pt-BR, e a traducao en ficava inalcancavel
    # na landing, no login e no cadastro.
    def switch_locale(&action)
      remember_visitor_locale
      locale = Current.family.try(:locale) || visitor_locale || I18n.default_locale
      I18n.with_locale(locale, &action)
    end

    # Sem isto, ?locale=en valeria so para a requisicao daquele link: bastava
    # clicar em "Entrar" e a pagina seguinte voltava para pt-BR.
    #
    # Cookie e nao sessao porque a escolha deve sobreviver ao fechar o
    # navegador -- quem le em ingles hoje le em ingles amanha. Nao e dado
    # pessoal nem identifica ninguem: e um de dois valores de uma lista branca.
    def remember_visitor_locale
      escolhido = params[:locale].presence
      return if escolhido.blank?

      valido = VISITOR_LOCALES.find { |l| l.to_s == escolhido.to_s }
      return if valido.nil?

      cookies[:locale] = { value: valido.to_s, expires: 1.year.from_now, same_site: :lax }
    end

    # O que o visitante escolheu, se escolheu algo valido.
    #
    # A lista branca nao e paranoia: I18n.with_locale aceita qualquer simbolo e
    # locale vindo de parametro alimenta lookup de traducao. Valor de fora so
    # entra depois de bater com VISITOR_LOCALES.
    def visitor_locale
      escolhido = params[:locale].presence || cookies[:locale].presence
      return nil if escolhido.blank?

      VISITOR_LOCALES.find { |l| l.to_s == escolhido.to_s }
    end

    def switch_timezone(&action)
      timezone = Current.family.try(:timezone) || Time.zone
      Time.use_zone(timezone, &action)
    end
end
