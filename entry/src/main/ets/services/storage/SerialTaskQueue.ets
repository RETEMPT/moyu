/** Keep read-modify-write operations together; a failed task does not stall later tasks. */
export class SerialTaskQueue {
  private tail: Promise<void> = Promise.resolve();

  run<T>(task: () => Promise<T>): Promise<T> {
    const result = this.tail.then(task);
    this.tail = result.then(() => {}, () => {});
    return result;
  }
}
