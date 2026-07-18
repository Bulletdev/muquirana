import { Controller } from "@hotwired/stimulus";

// Colapsa/expande uma secao do dashboard de relatorios (US-10) e persiste o
// estado em users.preferences via PATCH /reports/update_preferences.
export default class extends Controller {
  static targets = ["content", "chevron", "button"];
  static values = {
    sectionKey: String,
    collapsed: Boolean,
  };

  connect() {
    if (this.collapsedValue) {
      this.collapse(false);
    }
  }

  toggle(event) {
    event.preventDefault();
    if (this.collapsedValue) {
      this.expand();
    } else {
      this.collapse();
    }
  }

  handleToggleKeydown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      event.stopPropagation();
      this.toggle(event);
    }
  }

  collapse(persist = true) {
    this.contentTarget.classList.add("hidden");
    this.chevronTarget.classList.add("-rotate-90");
    this.collapsedValue = true;
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", "false");
    }
    if (persist) {
      this.savePreference(true);
    }
  }

  expand() {
    this.contentTarget.classList.remove("hidden");
    this.chevronTarget.classList.remove("-rotate-90");
    this.collapsedValue = false;
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", "true");
    }
    this.savePreference(false);
  }

  async savePreference(collapsed) {
    const preferences = {
      reports_collapsed_sections: {
        [this.sectionKeyValue]: collapsed,
      },
    };

    const csrfToken = document.querySelector('meta[name="csrf-token"]');
    if (!csrfToken) return;

    try {
      await fetch("/reports/update_preferences", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken.content,
        },
        body: JSON.stringify({ preferences }),
      });
    } catch (error) {
      console.error("[reports-section] failed to save preference:", error);
    }
  }
}
