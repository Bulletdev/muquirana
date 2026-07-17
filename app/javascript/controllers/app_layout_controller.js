import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="dialog"
export default class extends Controller {
  static targets = [
    "leftSidebar",
    "rightSidebar",
    "mobileSidebar",
    "leftResizeHandle",
    "rightResizeHandle",
  ];
  static classes = [
    "expandedSidebar",
    "collapsedSidebar",
    "expandedTransition",
    "collapsedTransition",
  ];

  openMobileSidebar() {
    this.mobileSidebarTarget.classList.remove("hidden");
  }

  closeMobileSidebar() {
    this.mobileSidebarTarget.classList.add("hidden");
  }

  toggleLeftSidebar() {
    const isOpen = this.leftSidebarTarget.classList.contains("w-full");
    this.#updateUserPreference("show_sidebar", !isOpen);
    this.#toggleSidebarWidth(
      this.leftSidebarTarget,
      isOpen,
      this.hasLeftResizeHandleTarget ? this.leftResizeHandleTarget : null,
    );
  }

  toggleRightSidebar() {
    const isOpen = this.rightSidebarTarget.classList.contains("w-full");
    this.#updateUserPreference("show_ai_sidebar", !isOpen);
    this.#toggleSidebarWidth(
      this.rightSidebarTarget,
      isOpen,
      this.hasRightResizeHandleTarget ? this.rightResizeHandleTarget : null,
    );
  }

  // Collapsing folds the panel to w-0; the resize handle must fold with it,
  // otherwise the absolutely-positioned divider lingers as a stray sliver over
  // the content area. `hidden` stays on the handle at all times; only `lg:block`
  // toggles, mirroring the server-rendered `collapsed` state.
  #toggleSidebarWidth(el, isCurrentlyOpen, handle = null) {
    if (isCurrentlyOpen) {
      el.classList.remove(...this.expandedSidebarClasses);
      el.classList.add(...this.collapsedSidebarClasses);
      handle?.classList.remove("lg:block");
    } else {
      el.classList.add(...this.expandedSidebarClasses);
      el.classList.remove(...this.collapsedSidebarClasses);
      handle?.classList.add("lg:block");
    }
  }

  #updateUserPreference(field, value) {
    fetch(`/users/${this.userIdValue}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content,
        Accept: "application/json",
      },
      body: new URLSearchParams({
        [`user[${field}]`]: value,
      }).toString(),
    });
  }
}
