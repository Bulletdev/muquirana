module Breadcrumbable
  extend ActiveSupport::Concern

  included do
    before_action :set_breadcrumbs
  end

  private
    # The default, unless specific controller or action explicitly overrides
    #
    # O `default:` reproduz o comportamento do upstream (`controller_name.titleize`)
    # para qualquer controller que ainda nao tenha chave em breadcrumbs.*, entao
    # nenhuma tela quebra por falta de traducao -- ela so continua em ingles.
    def set_breadcrumbs
      @breadcrumbs = [
        [ I18n.t("breadcrumbs.home"), root_path ],
        [ I18n.t("breadcrumbs.#{controller_name}", default: controller_name.titleize), nil ]
      ]
    end
end
