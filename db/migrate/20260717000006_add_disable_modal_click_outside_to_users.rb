class AddDisableModalClickOutsideToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :disable_modal_click_outside, :boolean, default: false, null: false
  end
end
