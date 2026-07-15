import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="confirm-dialog"
// See javascript/controllers/application.js for how this is wired up
export default class extends Controller {
  static targets = ["title", "subtitle", "confirmButton"];

  handleConfirm(rawData) {
    const data = this.#normalizeRawData(rawData);

    this.#prepareDialog(data);

    this.element.showModal();

    return new Promise((resolve) => {
      this.element.addEventListener(
        "close",
        () => {
          const isConfirmed = this.element.returnValue === "confirm";
          resolve(isConfirmed);
        },
        { once: true },
      );
    });
  }

  #prepareDialog(data) {
    const variant = data.variant || "primary";

    this.confirmButtonTargets.forEach((button) => {
      if (button.dataset.variant === variant) {
        button.removeAttribute("hidden");
      } else {
        button.setAttribute("hidden", true);
      }

      button.textContent = data.confirmText || "Confirm";
    });

    this.titleTarget.textContent = data.title || "Are you sure?";

    // textContent, NAO innerHTML.
    //
    // O body carrega nome de recurso escolhido pelo usuario -- veja
    // CustomConfirm.for_resource_deletion, usado com family_merchant.name e
    // user.display_name. Com innerHTML isso era XSS armazenado: o Rails escapa
    // o payload dentro do data-attribute, mas o JSON.parse aqui desfaz o
    // escape e o innerHTML executa o resultado.
    //
    // Nenhum call site precisa de markup no body: todos passam texto puro.
    this.subtitleTarget.textContent =
      data.body || "This action cannot be undone.";
  }

  // If data is a string, it's the title.  Otherwise, return the parsed object.
  #normalizeRawData(rawData) {
    try {
      const parsed = JSON.parse(rawData);

      if (typeof parsed === "boolean") {
        return { title: "Are you sure?" };
      }

      return parsed;
    } catch (e) {
      return { title: rawData };
    }
  }
}
