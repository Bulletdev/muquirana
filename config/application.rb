require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Muquirana
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "America/Sao_Paulo"
    # config.eager_load_paths << Rails.root.join("extras")

    # i18n
    #
    # available_locales restringe os 136 idiomas que o vendor de
    # config/locales/defaults/ carrega. Os arquivos continuam no disco: para
    # habilitar outro idioma basta adiciona-lo aqui.
    #
    # Isso restringe de graca dois pontos que derivam de I18n.available_locales:
    # a validacao de Family#locale (family.rb:36) e o seletor de idioma das
    # configuracoes (languages_helper.rb:357).
    #
    # :es tem apenas os defaults do Rails (datas, erros de validacao) -- nao ha
    # traducao das strings da aplicacao. A UI cai em ingles pelo fallback ate
    # que alguem traduza config/locales/views/**/es.yml.
    config.i18n.default_locale = :"pt-BR"
    config.i18n.available_locales = [ :"pt-BR", :en, :es ]

    # Precisa ser [:en] explicito, e nao `true`.
    #
    # `fallbacks = true` cai no default_locale. Com o default em :"pt-BR" isso
    # produziria dois problemas: espanhol cairia em portugues, e uma chave
    # faltando em pt-BR nao teria para onde cair -- apareceria "translation
    # missing" na tela. Como a traducao e incremental, o ingles precisa ser a
    # rede de seguranca de todos os idiomas.
    config.i18n.fallbacks = [ :en ]

    config.app_mode = (ENV["SELF_HOSTED"] == "true" || ENV["SELF_HOSTING_ENABLED"] == "true" ? "self_hosted" : "managed").inquiry

    # Self hosters can optionally set their own encryption keys if they want to use ActiveRecord encryption.
    if Rails.application.credentials.active_record_encryption.present?
      config.active_record.encryption = Rails.application.credentials.active_record_encryption
    end

    config.view_component.preview_controller = "LookbooksController"
    config.lookbook.preview_display_options = {
      theme: [ "light", "dark" ] # available in view as params[:theme]
    }

    # Enable Rack::Attack middleware for API rate limiting
    config.middleware.use Rack::Attack
  end
end
