import { ColorPalette } from '../constants/DesignTokens';
import { paletteForStyle } from './ThemeStyle';

/** Reader controls use the same chosen palette as settings and the library; document ink stays independent. */
export class ReaderTheme {
  static palette(dark: boolean, style: string = 'mono'): ColorPalette {
    return paletteForStyle(dark, style);
  }
}
