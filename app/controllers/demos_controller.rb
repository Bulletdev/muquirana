# Porta de entrada da instancia de demonstracao.
#
# O visitante clica em "Ver a demo" na landing e cai DENTRO do app, ja logado.
# Pedir e-mail e senha para quem so quer ver o produto seria um pedagio sem
# proposito -- a conta e publica e os dados sao ficticios.
#
# So existe onde DEMO_INSTANCE=true. Na instancia real (a que tem dinheiro de
# verdade) a rota responde 404, como se nao existisse -- porque nao existe.
class DemosController < ApplicationController
  skip_authentication

  before_action :ensure_demo_instance

  def create
    user = Demo::Session.user

    # Sem usuario de demo, a instancia ainda nao foi semeada. Melhor mandar
    # para o login com um aviso do que dar 500 na cara do visitante.
    return redirect_to new_session_path, alert: t(".not_seeded") if user.nil?

    @session = create_session_for(user)

    # dashboard_path e nao root_path: a raiz e a landing, que com sessao
    # redireciona para o painel de qualquer forma -- um salto a menos.
    redirect_to dashboard_path
  end

  private

    def ensure_demo_instance
      raise ActionController::RoutingError, "Not Found" unless Demo::DataCleaner.demo_instance?
    end
end
