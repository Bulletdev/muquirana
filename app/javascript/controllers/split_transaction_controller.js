import { Controller } from "@hotwired/stimulus";

// Handles the split-transaction modal: add/remove rows and keep a running
// "remaining" indicator so the user can only submit when the split amounts
// sum to the parent total. Amounts are entered as positive magnitudes; the
// server assigns the parent's sign.
export default class extends Controller {
  static targets = [
    "rowsContainer",
    "template",
    "amountInput",
    "remaining",
    "remainingContainer",
    "error",
    "submitButton",
  ];

  static values = { total: Number };

  connect() {
    this.index = this.amountInputTargets.length;
    this.updateRemaining();
  }

  addRow() {
    const html = this.templateTarget.innerHTML.replaceAll("__INDEX__", this.index);
    this.rowsContainerTarget.insertAdjacentHTML("beforeend", html);
    this.index += 1;
    this.updateRemaining();
  }

  removeRow(event) {
    const row = event.target.closest("[data-split-transaction-target='row']");
    if (row) row.remove();
    this.updateRemaining();
  }

  updateRemaining() {
    const sum = this.amountInputTargets.reduce((acc, input) => {
      const value = Number.parseFloat(input.value);
      return acc + (Number.isNaN(value) ? 0 : value);
    }, 0);

    const remaining = Math.round((this.totalValue - sum) * 100) / 100;
    const balanced = Math.abs(remaining) < 0.005;

    if (this.hasRemainingTarget) {
      this.remainingTarget.textContent = remaining.toFixed(2);
    }

    this.#toggleState(balanced);
  }

  #toggleState(balanced) {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = !balanced;
    }

    if (this.hasErrorTarget) {
      this.errorTarget.classList.toggle("hidden", balanced);
    }

    if (this.hasRemainingContainerTarget) {
      this.remainingContainerTarget.classList.toggle("border-destructive", !balanced);
      this.remainingContainerTarget.classList.toggle("border-secondary", balanced);
    }

    if (this.hasRemainingTarget) {
      this.remainingTarget.classList.toggle("text-destructive", !balanced);
      this.remainingTarget.classList.toggle("text-primary", balanced);
    }
  }
}
