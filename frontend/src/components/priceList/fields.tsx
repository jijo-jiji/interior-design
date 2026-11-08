import React, { useId, useState } from 'react';
import { formatWidthList, parseNumber, parseWidthList } from '../../catalogEditor.ts';

/* Small form controls for the price-list editor. Each commits a value only
   when what was typed is a usable number, so half-typed text ("4.", "") never
   reaches the price list. */

const input =
  'h-9 rounded-lg border bg-surface px-2 text-[13px] text-ink tabular-nums transition-colors hover:border-line-strong';

const border = (invalid: boolean) => (invalid ? 'border-danger' : 'border-line');

interface NumberFieldProps {
  /** Accessible name, e.g. "Price of Base 800 (RM)". */
  label: string;
  value: number;
  onChange: (value: number) => void;
  /** Shown after the box ("mm", "RM"). */
  unit?: string;
  /** Lowest/highest sensible value; outside it the box is marked. */
  min?: number;
  max?: number;
  className?: string;
}

export const NumberField: React.FC<NumberFieldProps> = ({ label, value, onChange, unit, min, max, className = 'w-24' }) => {
  const [text, setText] = useState(String(value));
  const [seen, setSeen] = useState(value);

  // Follow outside changes (discarding edits, loading another version), but
  // leave alone what is being typed when it already means this value.
  if (value !== seen) {
    setSeen(value);
    if (parseNumber(text) !== value) setText(String(value));
  }

  const typed = parseNumber(text);
  const outOfRange = typed !== null && ((min !== undefined && typed < min) || (max !== undefined && typed > max));
  const invalid = typed === null || outOfRange;

  return (
    <span className="inline-flex items-center gap-1.5">
      <input
        type="text"
        inputMode="decimal"
        aria-label={label}
        aria-invalid={invalid || undefined}
        value={text}
        onChange={(e) => {
          setText(e.target.value);
          const n = parseNumber(e.target.value);
          if (n !== null) onChange(n);
        }}
        onBlur={() => {
          if (typed === null) setText(String(value));
        }}
        className={`${input} ${border(invalid)} text-right ${className}`}
      />
      {unit && (
        <span className="text-xs text-ink-muted" aria-hidden>
          {unit}
        </span>
      )}
    </span>
  );
};

interface TextFieldProps {
  label: string;
  value: string;
  onChange: (value: string) => void;
  className?: string;
}

export const TextField: React.FC<TextFieldProps> = ({ label, value, onChange, className = 'w-full' }) => (
  <input
    type="text"
    aria-label={label}
    value={value}
    onChange={(e) => onChange(e.target.value)}
    className={`${input} ${border(false)} ${className}`}
  />
);

interface WidthListFieldProps {
  label: string;
  value: number[];
  onChange: (value: number[]) => void;
}

/** "300, 400, 450": the widths a layout may use. */
export const WidthListField: React.FC<WidthListFieldProps> = ({ label, value, onChange }) => {
  const [text, setText] = useState(formatWidthList(value));
  const [seen, setSeen] = useState(value);
  const typed = parseWidthList(text);

  if (value !== seen) {
    setSeen(value);
    if (!typed || formatWidthList(typed) !== formatWidthList(value)) setText(formatWidthList(value));
  }

  return (
    <input
      type="text"
      aria-label={`${label} (widths in mm, separated by commas)`}
      aria-invalid={typed === null || undefined}
      value={text}
      onChange={(e) => {
        setText(e.target.value);
        const parsed = parseWidthList(e.target.value);
        if (parsed) onChange(parsed);
      }}
      onBlur={() => {
        if (typed === null) setText(formatWidthList(value));
      }}
      className={`${input} ${border(typed === null)} w-full max-w-md text-left`}
    />
  );
};

interface CheckboxProps {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  hint?: string;
}

export const Checkbox: React.FC<CheckboxProps> = ({ label, checked, onChange, hint }) => {
  const id = useId();
  return (
    <span className="inline-flex items-start gap-2">
      <input
        id={id}
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        className="mt-0.5 h-4 w-4 cursor-pointer accent-clay"
      />
      <label htmlFor={id} className="cursor-pointer text-[13px] text-ink">
        {label}
        {hint && <span className="block text-xs text-ink-muted">{hint}</span>}
      </label>
    </span>
  );
};

/** A labelled row in a settings list. */
export const Row: React.FC<{ label: string; hint?: string; children: React.ReactNode }> = ({ label, hint, children }) => (
  <div className="flex flex-wrap items-center justify-between gap-x-6 gap-y-1 border-b border-line py-2.5 last:border-b-0">
    <div className="min-w-0 max-w-md">
      <div className="text-[13px] font-medium text-ink">{label}</div>
      {hint && <div className="text-xs text-ink-muted">{hint}</div>}
    </div>
    <div className="flex items-center gap-2">{children}</div>
  </div>
);
