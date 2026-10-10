/** Each reader owns only its edited fields; split panes must not overwrite each other's state. */
export type ReaderSaveKind = 'markdown' | 'pdf' | 'pdf-source' | 'handwriting' | 'scratchpad';
