class AddReportsPreferencesToUsers < ActiveRecord::Migration[7.2]
  def change
    # Coluna JSON de preferencias por usuario. Guarda o estado do dashboard de
    # relatorios (US-10): ordem das secoes e quais estao colapsadas. Fica generica
    # (nao "reports_*") para poder abrigar outras preferencias no futuro.
    add_column :users, :preferences, :jsonb, default: {}, null: false
  end
end
