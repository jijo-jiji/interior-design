/** Where a client project is in the sale. Same rules and words as the sales
 *  app (lib/shared/project_status.dart). */
export type ProjectStatus = 'draft' | 'quote' | 'deposit';

export const STATUS_LABELS: Record<ProjectStatus, string> = {
  draft: 'Draft',
  quote: 'Quote sent',
  deposit: 'Deposit paid',
};

export function statusOf(project: { deposit_paid?: number; status?: string }): ProjectStatus {
  if ((project.deposit_paid ?? 0) > 0) return 'deposit';
  if (project.status === 'draft') return 'draft';
  if (project.status === 'deposit' || project.status === 'deposit_paid' || project.status === 'priority_locked') {
    return 'deposit';
  }
  return 'quote';
}
