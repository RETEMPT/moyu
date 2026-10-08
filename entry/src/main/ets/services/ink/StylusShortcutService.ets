import { stylusInteraction } from '@kit.Penkit';

/** NearLink pairing belongs to the OS. Subscribe to the paired pen's public input events. */
export class StylusShortcutService {
  private static owner: StylusShortcutService | null = null;
  private doubleTap: ((event: stylusInteraction.DoubleTapEvent) => void) | undefined;
  private squeeze: ((event: stylusInteraction.SqueezeEvent) => void) | undefined;

  start(enabled: () => boolean, toggleEraser: () => void, showTools: () => void): void {
    this.stop();
    if (!canIUse('SystemCapability.Stylus.StylusService')) { return; }
    if (!StylusShortcutService.owner) { this.claim(); }
    this.doubleTap = () => { if (StylusShortcutService.owner === this && enabled()) { toggleEraser(); } };
    this.squeeze = () => { if (StylusShortcutService.owner === this && enabled()) { showTools(); } };
    try { stylusInteraction.on('doubleTap', this.doubleTap); }
    catch { this.doubleTap = undefined; }
    try { stylusInteraction.on('squeeze', this.squeeze); }
    catch { this.squeeze = undefined; }
  }

  claim(): void { StylusShortcutService.owner = this; }

  stop(): void {
    if (this.doubleTap) { try { stylusInteraction.off('doubleTap', this.doubleTap); } catch {} }
    if (this.squeeze) { try { stylusInteraction.off('squeeze', this.squeeze); } catch {} }
    this.doubleTap = undefined; this.squeeze = undefined;
    if (StylusShortcutService.owner === this) { StylusShortcutService.owner = null; }
  }
}
