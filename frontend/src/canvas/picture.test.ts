import { describe, expect, it } from 'vitest';
import { pictureFileName, pictureSize } from './picture.ts';

describe('picture size', () => {
  it('keeps the shape of the view the picture was taken from', () => {
    expect(pictureSize(1200, 750)).toEqual({ width: 2000, height: 1250 });
    expect(pictureSize(1000, 1000)).toEqual({ width: 2000, height: 2000 });
  });

  it('keeps an extreme window within sensible bounds', () => {
    expect(pictureSize(4000, 500).height).toBe(Math.round(2000 / 2.4));
    expect(pictureSize(300, 1200).height).toBe(2500);
  });

  it('falls back to a landscape picture for a view with no size', () => {
    expect(pictureSize(0, 0)).toEqual({ width: 2000, height: 1250 });
  });

  it('can be a different width', () => {
    expect(pictureSize(1600, 1000, 800)).toEqual({ width: 800, height: 500 });
  });
});

describe('picture file name', () => {
  it('names it for the quote', () => {
    expect(pictureFileName('QT-992AC14B')).toBe('kitchen-QT-992AC14B.png');
    expect(pictureFileName('QT-1/../x y', 'jpg')).toBe('kitchen-QT-1xy.jpg');
    expect(pictureFileName('')).toBe('kitchen-design.png');
  });
});
