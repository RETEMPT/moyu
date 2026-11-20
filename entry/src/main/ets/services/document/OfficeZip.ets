const DIRECTORY_END_SIZE: number = 22;
const MAX_DIRECTORY_ENTRIES: number = 4096;
const MAX_XML_PART: number = 2 * 1024 * 1024;
const MAX_COMPRESSED_XML_PART: number = MAX_XML_PART + 64 * 1024;
const MAX_TOTAL_XML: number = 8 * 1024 * 1024;
const DATA_DESCRIPTOR_FLAG: number = 0x0008;
const ENCRYPTION_FLAGS: number = 0x2041;

interface ZipEntry {
  offset: number;
  compressed: number;
  size: number;
  method: number;
  flags: number;
  crc: number;
}

export interface OfficeZipPart { data: ArrayBuffer; size: number; method: number; crc: number; }

/** Reads only the requested ZIP entries in memory. It never extracts paths to disk. */
export class OfficeZip {
  private readonly bytes: ArrayBuffer;
  private readonly view: DataView;
  private readonly entries: Map<string, ZipEntry> = new Map();
  private directory: number = 0;
  private totalRead: number = 0;

  constructor(bytes: ArrayBuffer) {
    this.bytes = bytes;
    this.view = new DataView(bytes);
    const end = this.directoryEnd();
    const entryCount = this.u16(end + 10);
    this.directory = this.u32(end + 16);
    if (this.u16(end + 4) || this.u16(end + 6) || this.u16(end + 8) !== entryCount ||
      entryCount === 0 || entryCount > MAX_DIRECTORY_ENTRIES || this.directory + this.u32(end + 12) !== end) {
      throw new Error('Office 文件目录无效，或使用了分卷与扩展 ZIP 格式。');
    }
    let offset = this.directory;
    for (let index = 0; index < entryCount; index++) {
      if (offset + 46 > end || this.u32(offset) !== 0x02014b50) { throw new Error('Office 文件目录损坏。'); }
      const length = this.u16(offset + 28);
      const next = offset + 46 + length + this.u16(offset + 30) + this.u16(offset + 32);
      if (length === 0 || next > end) { throw new Error('Office 文件条目不完整。'); }
      const name = this.name(offset + 46, length);
      if (name) {
        if (this.entries.has(name)) { throw new Error('Office 文件包含重复条目。'); }
        this.entries.set(name, { offset: this.u32(offset + 42), compressed: this.u32(offset + 20),
          size: this.u32(offset + 24), method: this.u16(offset + 10), flags: this.u16(offset + 8),
          crc: this.u32(offset + 16) });
      }
      offset = next;
    }
    if (offset !== end) { throw new Error('Office 文件目录长度不一致。'); }
  }

  part(name: string): OfficeZipPart {
    const entry = this.entries.get(name);
    if (!entry || entry.offset + 30 > this.directory || this.u32(entry.offset) !== 0x04034b50) {
      throw new Error('Office 文件缺少所需的正文条目。');
    }
    const pathLength = this.u16(entry.offset + 26);
    const start = entry.offset + 30 + pathLength + this.u16(entry.offset + 28);
    const stop = start + entry.compressed;
    const flags = this.u16(entry.offset + 6);
    if (stop > this.directory || this.name(entry.offset + 30, pathLength) !== name ||
      this.u16(entry.offset + 8) !== entry.method || flags !== entry.flags ||
      (flags & ENCRYPTION_FLAGS) !== 0 || ![0, 8].includes(entry.method)) {
      throw new Error('Office 正文条目损坏、已加密或使用了不支持的压缩方式。');
    }
    if (entry.size < 1 || entry.size > MAX_XML_PART || entry.compressed > MAX_COMPRESSED_XML_PART ||
      this.totalRead + entry.size > MAX_TOTAL_XML) {
      throw new Error('Office 正文超过导入上限，请先拆分文档。');
    }
    // Streaming writers put sizes and CRC in a descriptor; their data is checked after decoding.
    if (entry.compressed === 0 || (entry.method === 0 && entry.compressed !== entry.size) ||
      ((flags & DATA_DESCRIPTOR_FLAG) === 0 && (this.u32(entry.offset + 14) !== entry.crc ||
        this.u32(entry.offset + 18) !== entry.compressed || this.u32(entry.offset + 22) !== entry.size))) {
      throw new Error('Office 正文校验失败，条目文件头与目录不一致。');
    }
    this.totalRead += entry.size;
    return { data: this.bytes.slice(start, stop), size: entry.size, method: entry.method, crc: entry.crc };
  }

  private directoryEnd(): number {
    const size = this.bytes.byteLength;
    const lower = Math.max(0, size - DIRECTORY_END_SIZE - 65535);
    for (let offset = size - DIRECTORY_END_SIZE; offset >= lower; offset--) {
      if (this.u32(offset) === 0x06054b50 && offset + DIRECTORY_END_SIZE + this.u16(offset + 20) === size) { return offset; }
    }
    throw new Error('文件不是可读取的 Office 文档，或文件不完整。');
  }

  private name(start: number, length: number): string {
    // The standard OOXML parts accessed by this importer have ASCII names.
    if (length > 180) { return ''; }
    let name = '';
    for (let index = start; index < start + length; index++) {
      const unit = this.view.getUint8(index);
      if (unit < 32 || unit > 126) { return ''; }
      name += String.fromCharCode(unit);
    }
    return name;
  }

  private u16(offset: number): number { return this.view.getUint16(offset, true); }
  private u32(offset: number): number { return this.view.getUint32(offset, true); }
}
