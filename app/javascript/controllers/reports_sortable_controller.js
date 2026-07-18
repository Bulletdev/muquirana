import { Controller } from "@hotwired/stimulus";

// Reordena as secoes do dashboard de relatorios (US-10) por drag-and-drop
// (mouse), toque (com hold) e teclado, persistindo a ordem em
// users.preferences via PATCH /reports/update_preferences.
export default class extends Controller {
  static targets = ["section", "handle"];
  static values = {
    holdDelay: { type: Number, default: 150 },
  };

  connect() {
    this.draggedElement = null;
    this.touchStartY = 0;
    this.currentTouchY = 0;
    this.isTouching = false;
    this.keyboardGrabbedElement = null;
    this.holdTimer = null;
    this.holdActivated = false;
  }

  // ===== Mouse =====
  // O drag nativo parte da ALCA (grip), nao da secao inteira: uma secao
  // `draggable` inteira sequestra taps/scroll no mobile (o navegador inicia o
  // drag nativo, com aquele "fantasma" escuro, em vez do clique). A secao segue
  // como alvo de drop/dragover; aqui resolvemos a secao a partir da alca.
  dragStart(event) {
    const section = event.currentTarget.closest(
      "[data-reports-sortable-target='section']",
    );
    if (!section) return;

    this.draggedElement = section;
    section.classList.add("opacity-50");
    section.setAttribute("aria-grabbed", "true");
    event.dataTransfer.effectAllowed = "move";
  }

  dragEnd(event) {
    event.currentTarget.classList.remove("opacity-50");
    event.currentTarget.setAttribute("aria-grabbed", "false");
    this.clearPlaceholders();
  }

  dragOver(event) {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";

    const afterElement = this.getDragAfterElement(event.clientY);
    this.clearPlaceholders();

    if (afterElement == null) {
      this.showPlaceholder(this.element.lastElementChild, "after");
    } else {
      this.showPlaceholder(afterElement, "before");
    }
  }

  drop(event) {
    event.preventDefault();
    event.stopPropagation();

    const afterElement = this.getDragAfterElement(event.clientY);
    if (afterElement == null) {
      this.element.appendChild(this.draggedElement);
    } else {
      this.element.insertBefore(this.draggedElement, afterElement);
    }

    this.clearPlaceholders();
    this.saveOrder();
  }

  // ===== Touch (bound to the drag handle only, com hold) =====
  touchStart(event) {
    const section = event.currentTarget.closest(
      "[data-reports-sortable-target='section']",
    );
    if (!section) return;

    this.pendingSection = section;
    this.touchStartY = event.touches[0].clientY;
    this.currentTouchY = this.touchStartY;
    this.holdActivated = false;

    this.holdTimer = setTimeout(() => this.activateDrag(), this.holdDelayValue);
  }

  activateDrag() {
    if (!this.pendingSection) return;

    this.holdActivated = true;
    this.isTouching = true;
    this.draggedElement = this.pendingSection;
    this.draggedElement.classList.add("opacity-50", "scale-[1.02]");
    this.draggedElement.setAttribute("aria-grabbed", "true");

    if (navigator.vibrate) navigator.vibrate(30);
  }

  touchMove(event) {
    if (!this.holdActivated || !this.isTouching || !this.draggedElement) return;

    event.preventDefault();
    this.currentTouchY = event.touches[0].clientY;

    const afterElement = this.getDragAfterElement(this.currentTouchY);
    this.clearPlaceholders();

    if (afterElement == null) {
      this.showPlaceholder(this.element.lastElementChild, "after");
    } else {
      this.showPlaceholder(afterElement, "before");
    }
  }

  touchEnd() {
    this.cancelHold();

    if (!this.holdActivated || !this.isTouching || !this.draggedElement) {
      this.resetTouchState();
      return;
    }

    const afterElement = this.getDragAfterElement(this.currentTouchY);
    if (afterElement == null) {
      this.element.appendChild(this.draggedElement);
    } else {
      this.element.insertBefore(this.draggedElement, afterElement);
    }

    this.draggedElement.classList.remove("opacity-50", "scale-[1.02]");
    this.draggedElement.setAttribute("aria-grabbed", "false");
    this.clearPlaceholders();
    this.saveOrder();
    this.resetTouchState();
  }

  cancelHold() {
    if (this.holdTimer) {
      clearTimeout(this.holdTimer);
      this.holdTimer = null;
    }
  }

  resetTouchState() {
    this.isTouching = false;
    this.draggedElement = null;
    this.pendingSection = null;
    this.holdActivated = false;
  }

  // ===== Keyboard =====
  handleKeyDown(event) {
    const currentSection = event.currentTarget;

    switch (event.key) {
      case "ArrowUp":
        if (this.keyboardGrabbedElement === currentSection) {
          event.preventDefault();
          this.moveUp(currentSection);
        }
        break;
      case "ArrowDown":
        if (this.keyboardGrabbedElement === currentSection) {
          event.preventDefault();
          this.moveDown(currentSection);
        }
        break;
      case "Enter":
      case " ":
        event.preventDefault();
        this.toggleGrabMode(currentSection);
        break;
      case "Escape":
        if (this.keyboardGrabbedElement) {
          event.preventDefault();
          this.releaseKeyboardGrab();
        }
        break;
    }
  }

  toggleGrabMode(section) {
    if (this.keyboardGrabbedElement === section) {
      this.releaseKeyboardGrab();
    } else {
      this.grabWithKeyboard(section);
    }
  }

  grabWithKeyboard(section) {
    if (this.keyboardGrabbedElement) this.releaseKeyboardGrab();

    this.keyboardGrabbedElement = section;
    section.setAttribute("aria-grabbed", "true");
    section.classList.add("ring-2", "ring-primary", "ring-offset-2");
  }

  releaseKeyboardGrab() {
    if (!this.keyboardGrabbedElement) return;

    this.keyboardGrabbedElement.setAttribute("aria-grabbed", "false");
    this.keyboardGrabbedElement.classList.remove(
      "ring-2",
      "ring-primary",
      "ring-offset-2",
    );
    this.keyboardGrabbedElement = null;
    this.saveOrder();
  }

  moveUp(section) {
    const previousSibling = section.previousElementSibling;
    if (previousSibling?.hasAttribute("data-section-key")) {
      this.element.insertBefore(section, previousSibling);
      section.focus();
    }
  }

  moveDown(section) {
    const nextSibling = section.nextElementSibling;
    if (nextSibling?.hasAttribute("data-section-key")) {
      this.element.insertBefore(nextSibling, section);
      section.focus();
    }
  }

  getDragAfterElement(y) {
    const draggableElements = this.sectionTargets.filter(
      (section) => section !== this.draggedElement,
    );

    return draggableElements.reduce(
      (closest, child) => {
        const box = child.getBoundingClientRect();
        const offset = y - box.top - box.height / 2;
        if (offset < 0 && offset > closest.offset) {
          return { offset: offset, element: child };
        }
        return closest;
      },
      { offset: Number.NEGATIVE_INFINITY },
    ).element;
  }

  showPlaceholder(element, position) {
    if (!element) return;
    if (position === "before") {
      element.classList.add("border-t-4", "border-primary");
    } else {
      element.classList.add("border-b-4", "border-primary");
    }
  }

  clearPlaceholders() {
    this.sectionTargets.forEach((section) => {
      section.classList.remove("border-t-4", "border-b-4", "border-primary");
    });
  }

  async saveOrder() {
    const order = this.sectionTargets.map(
      (section) => section.dataset.sectionKey,
    );

    const csrfToken = document.querySelector('meta[name="csrf-token"]');
    if (!csrfToken) return;

    try {
      await fetch("/reports/update_preferences", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken.content,
        },
        body: JSON.stringify({ preferences: { reports_section_order: order } }),
      });
    } catch (error) {
      console.error("[reports-sortable] failed to save order:", error);
    }
  }
}
