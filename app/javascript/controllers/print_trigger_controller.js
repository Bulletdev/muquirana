import { Controller } from "@hotwired/stimulus";

// Dispara a caixa de dialogo de impressao do navegador na versao de impressao
// dos relatorios (US-10).
export default class extends Controller {
  print() {
    window.print();
  }
}
