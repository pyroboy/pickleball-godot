"""Shared look of the proposal PDF: colours and drawing helpers, copied from the original
generator (branch archive/main-wip-2026-11, docs/pixel_art_test/generator/make_pdf.py)."""
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, Color
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
W, H = 960, 540
M = 48

BG = HexColor("#fbfaf7"); INK = HexColor("#16151a"); SUB = HexColor("#4f4d48")
MUTED = HexColor("#8a877f"); LINE = HexColor("#e2ded5"); CARD = HexColor("#ffffff")
ORANGE = HexColor("#eb6834"); BLUE = HexColor("#2a78d6"); AQUA = HexColor("#1baf7a")
VIOLET = HexColor("#6250d6"); YELLOW = HexColor("#eda100"); RED = HexColor("#e34948")
NIGHT = HexColor("#1e1b2f"); NIGHT2 = HexColor("#2c2745")
GRASS = HexColor("#5f9a4a"); GRASS_D = HexColor("#3f7340"); GRASS_SH = HexColor("#35585a")
COURT = HexColor("#2f6fae"); KITCHEN = HexColor("#4a8cc9"); DIRT = HexColor("#c9b48a")

def P(size=11, color=INK, lead=None, font="Helvetica", align=0):
    return ParagraphStyle("p", fontName=font, fontSize=size, leading=lead or size * 1.38,
                          textColor=color, alignment=align)

def para(c, text, x, ytop, w, style):
    p = Paragraph(text, style)
    _, h = p.wrap(w, 1000)
    p.drawOn(c, x, ytop - h)
    return h

def bullets(c, items, x, ytop, w, size=11, gap=5, color=INK, dot=ORANGE):
    y = ytop
    for it in items:
        c.setFillColor(dot); c.circle(x + 3, y - size * 0.55, 2.4, stroke=0, fill=1)
        h = para(c, it, x + 13, y, w - 13, P(size, color))
        y -= h + gap
    return ytop - y

def bg(c, color=BG):
    c.setFillColor(color); c.rect(0, 0, W, H, stroke=0, fill=1)

page_no = [0]
def header(c, kicker, title, dark=False):
    page_no[0] += 1
    bg(c, NIGHT if dark else BG)
    c.setFillColor(ORANGE); c.rect(M, H - 38, 26, 4, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 9.5); c.setFillColor(ORANGE)
    c.drawString(M + 34, H - 40, kicker.upper())
    c.setFont("Helvetica-Bold", 25); c.setFillColor(HexColor("#f4f1ea") if dark else INK)
    c.drawString(M, H - 70, title)
    c.setFont("Helvetica", 8.5); c.setFillColor(MUTED)
    c.drawRightString(W - M, 22, "Pickleball 2.5D  ·  graphics & performance proposal  ·  %d" % page_no[0])

def box(c, x, y, w, h, fill=CARD, stroke=LINE, r=8, lw=1):
    c.setFillColor(fill); c.setStrokeColor(stroke); c.setLineWidth(lw)
    c.roundRect(x, y, w, h, r, stroke=1 if stroke else 0, fill=1)

def tag(c, x, y, text, color, txt=HexColor("#ffffff"), size=8.5):
    c.setFont("Helvetica-Bold", size)
    tw = c.stringWidth(text, "Helvetica-Bold", size)
    c.setFillColor(color); c.roundRect(x, y, tw + 12, size + 8, 4, stroke=0, fill=1)
    c.setFillColor(txt); c.drawString(x + 6, y + 4.6, text)
    return tw + 12

def arrow(c, x1, y1, x2, y2, color=SUB, lw=1.6, head=7):
    import math
    c.setStrokeColor(color); c.setFillColor(color); c.setLineWidth(lw)
    c.line(x1, y1, x2, y2)
    a = math.atan2(y2 - y1, x2 - x1)
    p = c.beginPath()
    p.moveTo(x2, y2)
    p.lineTo(x2 - head * math.cos(a - 0.45), y2 - head * math.sin(a - 0.45))
    p.lineTo(x2 - head * math.cos(a + 0.45), y2 - head * math.sin(a + 0.45))
    p.close(); c.drawPath(p, stroke=0, fill=1)

def check(c, x, y, color=AQUA, s=1.0):
    c.setStrokeColor(color); c.setLineWidth(2.2 * s)
    p = c.beginPath(); p.moveTo(x, y + 4 * s); p.lineTo(x + 3.5 * s, y); p.lineTo(x + 10 * s, y + 9 * s)
    c.drawPath(p, stroke=1, fill=0)

def cross(c, x, y, color=RED, s=1.0):
    c.setStrokeColor(color); c.setLineWidth(2.2 * s)
    c.line(x, y, x + 8 * s, y + 8 * s); c.line(x, y + 8 * s, x + 8 * s, y)

