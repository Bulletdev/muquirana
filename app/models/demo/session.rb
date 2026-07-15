# Quem e o usuario que o visitante "vira" ao entrar na demo.
#
# Existe para o e-mail nao ficar escrito em tres lugares (controller, rake task
# e teste) e sair do lugar em dois deles.
class Demo::Session
  # .local nao e um dominio roteavel: nenhum e-mail sai daqui por acidente.
  EMAIL = "demo@muquirana.local"

  def self.user
    User.find_by(email: EMAIL)
  end
end
