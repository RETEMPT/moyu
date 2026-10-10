import { PdfPageModel } from '../../common/types/PdfAnnotationTypes';

/** LazyForEach creates page components for the visible range instead of the entire textbook. */
export class PdfPageDataSource implements IDataSource {
  private pages: PdfPageModel[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.pages.length; }
  getData(index: number): PdfPageModel { return this.pages[index]; }
  setPages(pages: PdfPageModel[]): void {
    this.pages = pages;
    for (const listener of this.listeners) { listener.onDataReloaded(); }
  }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener); if (index >= 0) { this.listeners.splice(index, 1); }
  }
}
