"""Create image-only PDF pages for explicit scan/import/annotation testing.

The image is a rendering of our own reading fixture; no third-party material,
personal data, or generated page substitutes are used in the reader.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

from pypdf import PdfReader
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "entry/src/main/resources/rawfile/example-course.pdf"
OUTPUT = ROOT / "entry/src/main/resources/rawfile/example-snapshot.pdf"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--renderer", default="pdftoppm", help="Poppler pdftoppm executable")
    args = parser.parse_args()
    source = PdfReader(SOURCE)
    temporary_root = ROOT / "tmp/pdfs"
    temporary_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="flowmind-pdf-", dir=temporary_root) as temporary:
        prefix = Path(temporary) / "page"
        subprocess.run([args.renderer, "-png", "-r", "144", str(SOURCE), str(prefix)], check=True)
        pdf = canvas.Canvas(str(OUTPUT), invariant=1)
        pdf.setTitle("墨语快照导入测试")
        pdf.setAuthor("FlowMind")
        for index, page in enumerate(source.pages, 1):
            width, height = float(page.mediabox.width), float(page.mediabox.height)
            pdf.setPageSize((width, height))
            pdf.drawImage(ImageReader(str(Path(temporary) / f"page-{index}.png")), 0, 0, width=width, height=height)
            pdf.showPage()
        pdf.save()

    reader = PdfReader(OUTPUT)
    assert len(reader.pages) == len(PdfReader(SOURCE).pages) == 2
    for page in reader.pages:
        assert not page.extract_text().strip(), "Snapshot must have no text layer"
        images = page["/Resources"]["/XObject"].get_object().values()
        assert any(item.get_object()["/Subtype"] == "/Image" for item in images)
    print(str(OUTPUT) + " - 2 image-only A4 pages; OCR needs native device validation")


if __name__ == "__main__":
    main()
