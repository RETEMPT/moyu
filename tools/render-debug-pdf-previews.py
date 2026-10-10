"""Render the bundled PDFs for debug-only preview on emulators without PDF Kit."""
import argparse
import subprocess
from pathlib import Path

from pypdf import PdfReader

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / 'entry/src/main/resources/rawfile'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--renderer', default='pdftoppm')
    args = parser.parse_args()
    output = RAW / 'debug-pdf-preview'
    output.mkdir(parents=True, exist_ok=True)
    for kind in ['course', 'snapshot']:
        source = RAW / f'example-{kind}.pdf'
        assert len(PdfReader(source).pages) == 2
        subprocess.run([args.renderer, '-png', '-scale-to-x', '1200', '-scale-to-y', '-1',
                        str(source), str(output / kind)], check=True)
        for page in [1, 2]:
            assert (output / f'{kind}-{page}.png').is_file()
    print('Rendered four original PDF pages for debug preview.')


if __name__ == '__main__':
    main()
