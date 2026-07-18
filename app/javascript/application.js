// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";

window.Turbo.StreamActions.redirect = function () {
  window.Turbo.visit(this.target);
};
