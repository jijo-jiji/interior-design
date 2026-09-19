import React from 'react';

/* ─────────────────────────────────────────────────────────────────────────────
   Shared studio primitives.
   The header, dock and inspector all used to hand-roll the same pill button,
   each with its own hex colours. They share these instead.
   ──────────────────────────────────────────────────────────────────────────── */

export interface SegmentOption<T extends string> {
  value: T;
  label: string;
  icon?: React.ReactNode;
  title?: string;
}

interface SegmentedControlProps<T extends string> {
  options: SegmentOption<T>[];
  value: T;
  onChange: (value: T) => void;
  /** Accessible name for the group, e.g. "Camera view". */
  label: string;
  size?: 'sm' | 'md';
  className?: string;
}

export function SegmentedControl<T extends string>({
  options,
  value,
  onChange,
  label,
  size = 'md',
  className = '',
}: SegmentedControlProps<T>) {
  const pad = size === 'sm' ? 'px-2.5 py-1.5' : 'px-3 py-1.5';

  return (
    <div
      role="group"
      aria-label={label}
      className={`flex items-center gap-0.5 rounded-xl border border-line bg-surface-muted p-0.5 ${className}`}
    >
      {options.map((opt) => {
        const active = opt.value === value;
        return (
          <button
            key={opt.value}
            type="button"
            aria-pressed={active}
            title={opt.title ?? opt.label}
            onClick={() => onChange(opt.value)}
            className={`${pad} flex items-center gap-1.5 rounded-lg text-[13px] font-medium whitespace-nowrap transition-colors cursor-pointer ${
              active
                ? 'bg-espresso text-surface-muted shadow-sm'
                : 'text-ink-muted hover:bg-surface hover:text-ink'
            }`}
          >
            {opt.icon}
            <span>{opt.label}</span>
          </button>
        );
      })}
    </div>
  );
}

type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger';

const VARIANTS: Record<ButtonVariant, string> = {
  primary: 'bg-espresso text-surface-muted hover:bg-espresso-deep border-espresso',
  secondary: 'bg-surface text-ink border-line hover:border-line-strong hover:bg-surface-muted',
  ghost: 'bg-transparent text-ink-muted border-transparent hover:bg-surface-sunken hover:text-ink',
  danger: 'bg-danger-tint text-danger border-danger/25 hover:bg-danger/15',
};

interface ActionButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  icon?: React.ReactNode;
}

export const ActionButton: React.FC<ActionButtonProps> = ({
  variant = 'secondary',
  icon,
  children,
  className = '',
  ...rest
}) => (
  <button
    type="button"
    {...rest}
    className={`inline-flex items-center justify-center gap-2 rounded-xl border px-3 py-2 text-[13px] font-medium transition-colors cursor-pointer disabled:cursor-not-allowed disabled:opacity-45 ${VARIANTS[variant]} ${className}`}
  >
    {icon}
    {children}
  </button>
);

interface LinkButtonProps extends React.AnchorHTMLAttributes<HTMLAnchorElement> {
  icon?: React.ReactNode;
}

export const LinkButton: React.FC<LinkButtonProps> = ({ icon, children, className = '', ...rest }) => (
  <a
    {...rest}
    className={`inline-flex items-center justify-center gap-2 rounded-xl border border-line bg-surface px-3 py-2 text-[13px] font-medium text-ink transition-colors hover:border-line-strong hover:bg-surface-muted ${className}`}
  >
    {icon}
    {children}
  </a>
);

/** Small uppercase section heading used throughout the side panels. */
export const SectionLabel: React.FC<{ children: React.ReactNode; className?: string }> = ({
  children,
  className = '',
}) => (
  <h3
    className={`text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-muted ${className}`}
  >
    {children}
  </h3>
);
