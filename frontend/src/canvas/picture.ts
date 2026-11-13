/** Gives the page a way to take a picture of what the canvas shows. */
export type PictureFn = () => string | null;

/** Anything with `userData.noPicture` (a selection outline, say) is left out. */
export const NO_PICTURE = { noPicture: true };

/** Size of a saved picture: [targetWidth] wide, in the shape of the view it
 *  was taken from (a very wide or tall window is kept within sensible bounds). */
export function pictureSize(viewWidth: number, viewHeight: number, targetWidth = 2000): { width: number; height: number } {
  const aspect = viewWidth > 0 && viewHeight > 0 ? viewWidth / viewHeight : 1.6;
  const clamped = Math.min(2.4, Math.max(0.8, aspect));
  return { width: targetWidth, height: Math.round(targetWidth / clamped) };
}

/** "kitchen-QT-ABC123.png" */
export const pictureFileName = (quoteId: string, ext = 'png') =>
  `kitchen-${quoteId.replace(/[^A-Za-z0-9-]/g, '') || 'design'}.${ext}`;
