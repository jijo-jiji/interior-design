import type { Catalog } from './pricing';
import sample from '../../assets/catalog/default_catalog.json';

/** The sample catalogue (the same file the office server seeds from and the
 *  sales app embeds). Used until /api/catalog answers, or if it never does. */
export const FALLBACK_CATALOG = sample as unknown as Catalog;
