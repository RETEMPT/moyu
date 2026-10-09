"""Create the explicit, two-page reading fixture; no first-launch library injection."""
import argparse
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parent.parent
PAGES = [
    ('墨语阅读测试', '01 / READ', [
        ('中文与英文', ['这是一份真实的 PDF，供手动导入、阅读、批注和文字提取测试。',
                       '中文段落、English text、数字 1234567890 均应清楚显示。',
                       '保留原 PDF 后，关闭应用再打开，页面与页数应保持一致。']),
        ('课程记录', ['课程：微积分入门', '任务：2026 年 10 月 12 日前提交课程练习。',
                    '来源：本测试文件第 1 页；整理待办后请自行核对。']),
        ('符号与表达式', ['α + β = γ     x² + y² = 1', '∫ f(x) dx = F(x) + C',
                       '标点示例：中文，句号。括号（说明）与英文 "quotes"。'])]),
    ('阅读与书写检查', '02 / WRITE', [
        ('检查顺序', ['1. 在设置 - 使用指南主动导入，再到“示例资料”中打开。',
                    '2. 默认只读；点击批注，使用画笔、荧光笔和橡皮擦。',
                    '3. 批注中返回应先回到只读，再次返回才关闭资料。',
                    '4. 提取并校对文字，然后在墨客引用此文件检索原文。']),
        ('空白练习区域', ['在下方书写一段笔记，测试缩放、撤销与重做。']),
        ('说明', ['此文档为墨语原创测试资料，不包含试卷、私人信息或模型密钥。',
                '它不会自动加入首次启动的资料库。'])])]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--font', required=True)
    args = parser.parse_args()
    font = TTFont('FixtureText', args.font)
    text = ''.join(title + badge + ''.join(h + ''.join(lines) for h, lines in sections)
                   for title, badge, sections in PAGES) + 'FlowMind - 1.0.3'
    missing = sorted(set(text) - {chr(c) for c in font.face.charToGlyph})
    if missing:
        raise ValueError('Missing test glyphs: ' + ''.join(missing))
    pdfmetrics.registerFont(font)
    output = ROOT / 'entry/src/main/resources/rawfile/example-course.pdf'
    output.parent.mkdir(parents=True, exist_ok=True)
    pdf = canvas.Canvas(str(output), pagesize=(595.28, 841.89), invariant=1)
    pdf.setTitle('墨语阅读测试')
    pdf.setAuthor('FlowMind')
    for number, (title, badge, sections) in enumerate(PAGES, 1):
        pdf.setFillColorRGB(.97, .97, .99)
        pdf.rect(0, 0, 595.28, 841.89, fill=1, stroke=0)
        pdf.setFillColorRGB(.40, .27, .65)
        pdf.setFont('FixtureText', 11)
        pdf.drawString(48, 786, badge)
        pdf.setFont('FixtureText', 26)
        pdf.drawString(48, 746, title)
        y = 676
        for heading, lines in sections:
            pdf.setFillColorRGB(.22, .18, .30)
            pdf.setFont('FixtureText', 15)
            pdf.drawString(48, y, heading)
            y -= 31
            pdf.setFont('FixtureText', 11)
            pdf.setFillColorRGB(.33, .31, .38)
            for line in lines:
                if pdfmetrics.stringWidth(line, 'FixtureText', 11) > 499:
                    raise ValueError('Fixture text would overflow: ' + line)
                pdf.drawString(48, y, line)
                y -= 25
            y -= 24
        if number == 2:
            pdf.setStrokeColorRGB(.83, .81, .87)
            pdf.roundRect(48, 124, 499, 164, 12, stroke=1, fill=0)
        pdf.setFillColorRGB(.48, .45, .53)
        pdf.setFont('FixtureText', 10)
        pdf.drawString(48, 55, 'FlowMind - 1.0.3')
        pdf.drawRightString(547, 55, str(number) + ' / 2')
        pdf.showPage()
    pdf.save()
    reader = PdfReader(output)
    assert len(reader.pages) == 2
    assert '中文' in reader.pages[0].extract_text()
    assert '再次返回' in reader.pages[1].extract_text()
    for page in reader.pages:
        fonts = page['/Resources']['/Font'].get_object().values()
        assert any('/FontFile2' in f.get_object()['/FontDescriptor'].get_object()
                   for f in fonts if '/FontDescriptor' in f.get_object())
    print(str(output) + ' - 2 pages; Unicode extraction and embedded fonts verified')

if __name__ == '__main__':
    main()
