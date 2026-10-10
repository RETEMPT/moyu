export interface CanvasToolState {
  tool: string;
  width: number;
  color: string;
  fingerDrawing: boolean;
  eraserMode: string;
}

/** One command carries all its data; watchers never depend on sibling prop update order. */
export interface CanvasToolCommand {
  sequence: number;
  target: string;
  action: string;
  value: string;
}
