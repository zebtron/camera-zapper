from pathlib import Path
import re
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Image, PageBreak, KeepTogether, ListFlowable, ListItem

ROOT = Path(__file__).parent
SOURCE = ROOT / "USER_MANUAL.md"
OUTPUT = ROOT / "Zebtron-Camera-Zapper-1.349-User-Manual.pdf"

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="ManualTitle", parent=styles["Title"], fontName="Helvetica-Bold", fontSize=25, leading=30, textColor=colors.HexColor("#1467D2"), alignment=TA_CENTER, spaceAfter=10))
styles.add(ParagraphStyle(name="ManualSubtitle", parent=styles["Normal"], fontSize=11, leading=15, textColor=colors.HexColor("#59636E"), alignment=TA_CENTER, spaceAfter=20))
styles.add(ParagraphStyle(name="H1Manual", parent=styles["Heading1"], fontName="Helvetica-Bold", fontSize=18, leading=22, textColor=colors.HexColor("#10253F"), spaceBefore=14, spaceAfter=8))
styles.add(ParagraphStyle(name="H2Manual", parent=styles["Heading2"], fontName="Helvetica-Bold", fontSize=13, leading=17, textColor=colors.HexColor("#1467D2"), spaceBefore=10, spaceAfter=5))
styles.add(ParagraphStyle(name="BodyManual", parent=styles["BodyText"], fontSize=9.5, leading=13.5, textColor=colors.HexColor("#263442"), spaceAfter=7))
styles.add(ParagraphStyle(name="FooterManual", parent=styles["Normal"], fontSize=7.5, textColor=colors.HexColor("#6C7680")))

def inline(text):
    text = re.sub(r"`([^`]+)`", r"<font name='Courier'>\1</font>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"<(https?://[^>]+)>", r"<link href='\1' color='#1467D2'>\1</link>", text)
    text = re.sub(r"<([^<>@ ]+@[^<> ]+)>", r"<link href='mailto:\1' color='#1467D2'>\1</link>", text)
    return text.replace("&", "&amp;").replace("&amp;lt;", "&lt;").replace("&amp;gt;", "&gt;")

def footer(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(colors.HexColor("#D6DCE2")); canvas.line(0.7*inch, 0.52*inch, 7.8*inch, 0.52*inch)
    canvas.setFont("Helvetica", 7.5); canvas.setFillColor(colors.HexColor("#6C7680"))
    canvas.drawString(0.7*inch, 0.35*inch, "Zebtron Camera Zapper 1.349 - Controlled Beta")
    canvas.drawRightString(7.8*inch, 0.35*inch, f"Page {doc.page}")
    canvas.restoreState()

doc = SimpleDocTemplate(str(OUTPUT), pagesize=letter, rightMargin=0.7*inch, leftMargin=0.7*inch, topMargin=0.65*inch, bottomMargin=0.68*inch, title="Zebtron Camera Zapper 1.349 User Manual", author="Zebtron")
story = [Spacer(1, 0.15*inch), Paragraph("Zebtron Camera Zapper", styles["ManualTitle"]), Paragraph("Automated backup for macOS - move, sync, and delete safely", styles["ManualSubtitle"])]
shot = ROOT / "Screenshots" / "dashboard-1.348.png"
if shot.exists():
    image = Image(str(shot)); image._restrictSize(7.05*inch, 3.72*inch); story += [image, Spacer(1, 0.22*inch)]
story += [Paragraph("Version 1.349 controlled beta", styles["H2Manual"]), Paragraph("A safety-first workflow for verified Android, camera-card, local, NAS, photo-library, cloud, and catalog destinations.", styles["BodyManual"]), PageBreak()]
wizard_shot = ROOT / "Screenshots" / "setup-wizard-1.348.png"
if wizard_shot.exists():
    story += [Paragraph("First-run Setup Wizard", styles["H1Manual"]), Paragraph("A new installation begins with a neutral, guided setup experience. Nothing is reported as an error until the user has chosen and configured that service.", styles["BodyManual"])]
    image = Image(str(wizard_shot)); image._restrictSize(7.05*inch, 4.0*inch); story += [image, PageBreak()]

lines = SOURCE.read_text().splitlines()[3:]
bullets = []
def flush():
    global bullets
    if bullets:
        story.append(ListFlowable([ListItem(Paragraph(inline(x), styles["BodyManual"])) for x in bullets], bulletType="bullet", leftIndent=18, bulletFontSize=6, spaceAfter=6))
        bullets = []

for line in lines:
    s = line.strip()
    if not s or s.startswith("!["):
        flush(); continue
    if s.startswith("## "):
        flush(); story.append(Paragraph(inline(s[3:]), styles["H1Manual"])); continue
    if s.startswith("### "):
        flush()
        story.append(Paragraph(inline(s[4:]), styles["H2Manual"])); continue
    if re.match(r"^\d+\. ", s):
        bullets.append(re.sub(r"^\d+\. ", "", s)); continue
    if s.startswith("- "):
        bullets.append(s[2:]); continue
    flush(); story.append(Paragraph(inline(s), styles["BodyManual"]))
flush()
doc.build(story, onFirstPage=footer, onLaterPages=footer)
print(OUTPUT)
