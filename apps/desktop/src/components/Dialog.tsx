import { useEffect, useRef } from "react";
import type { ReactNode } from "react";
import { X } from "lucide-react";

export function Dialog({
  title,
  children,
  onClose,
  closeLabel,
  className = "",
  locked = false,
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
  closeLabel: string;
  className?: string;
  locked?: boolean;
}) {
  const dialog = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const element = dialog.current;
    element?.focus();
    function keydown(event: KeyboardEvent) {
      if (event.key === "Escape" && !locked) {
        event.preventDefault();
        onClose();
      }
      if (event.key !== "Tab" || !element) return;
      const items = Array.from(
        element.querySelectorAll<HTMLElement>(
          'button:not(:disabled), input:not(:disabled), select:not(:disabled), [tabindex="0"]',
        ),
      );
      const first = items[0],
        last = items[items.length - 1];
      if (
        event.shiftKey &&
        (document.activeElement === first || document.activeElement === element)
      ) {
        event.preventDefault();
        last?.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first?.focus();
      }
    }
    element?.addEventListener("keydown", keydown);
    return () => {
      element?.removeEventListener("keydown", keydown);
      previous?.focus();
    };
  }, [locked, onClose]);
  return (
    <div className="modal-backdrop">
      <div
        className={`dialog ${className}`}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        ref={dialog}
      >
        <header className="dialog-header">
          <h1>{title}</h1>
          <button
            className="icon-button"
            onClick={onClose}
            disabled={locked}
            aria-label={closeLabel}
          >
            <X />
          </button>
        </header>
        {children}
      </div>
    </div>
  );
}
