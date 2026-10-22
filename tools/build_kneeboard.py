"""Rebuild the eight-page English kneeboard with ReportLab and Poppler."""
import pathlib,argparse,json,re,subprocess,shutil
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor,Color,white
from reportlab.platypus import Paragraph,Table,TableStyle
from reportlab.lib.styles import ParagraphStyle
from PIL import Image
from lua_data import Parser,walk
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--font-dir',type=pathlib.Path,default=pathlib.Path('C:/Windows/Fonts'),help='Folder containing Arial, Arial Narrow and Consolas TTF files')
p.add_argument('--pdftoppm',default='pdftoppm',help='Poppler pdftoppm executable or its path')
p.add_argument('--output-dir',type=pathlib.Path,default=ROOT/'work/kneeboard')
args=p.parse_args()
WORK=args.output_dir;WORK.mkdir(parents=True,exist_ok=True)
PDF=WORK/'MiG29A_FF_Kneeboard_EN.pdf'
mtree=Parser((ROOT/'mission/mission').read_text(encoding='utf-8-sig')).assignment()
mission=mtree.value;zones=list(mission['triggers']['zones'].values())
FONTS=args.font_dir
for name,file in [('Body','arial.ttf'),('Bold','arialbd.ttf'),('Head','ARIALNB.TTF'),('Mono','consola.ttf'),('MonoB','consolab.ttf')]: pdfmetrics.registerFont(TTFont(name,str(FONTS/file)))
PAPER=HexColor('#F3F0E7'); INK=HexColor('#182D39'); SLATE=HexColor('#51636C'); RED=HexColor('#A44335'); LIGHT=HexColor('#E3E4DC'); OLIVE=HexColor('#596858')
W,H=384,512; LEFT=22; WIDTH=340
c=canvas.Canvas(str(PDF),pagesize=(W,H),pageCompression=1)
c.setTitle('MiG-29A Fulcrum - Operational Conversion Course - English Kneeboard')
c.setAuthor('Iron87Ita - original campaign; personal MiG-29A FF adaptation')
page_no=0; layout=[]
def para(text,y,x=LEFT,width=WIDTH,size=11.3,leading=14.6,color=INK,bold=False):
    p=Paragraph(text,ParagraphStyle('p',fontName='Bold' if bold else 'Body',fontSize=size,leading=leading,textColor=color,spaceAfter=0,allowWidows=0,allowOrphans=0))
    _,h=p.wrap(width,1000)
    assert y-h>=31,('Overflow',page_no,text[:80],y,h)
    p.drawOn(c,x,y-h); layout.append({'page':page_no,'text':re.sub('<[^>]+>','',text),'box':[x,y-h,width,h]})
    return y-h
def label(text,y):
    c.setFont('MonoB',8.6);c.setFillColor(SLATE);c.drawString(LEFT,y,text);return y-14
def header(section,title,sub):
    global page_no
    page_no+=1
    c.setFillColor(PAPER);c.rect(0,0,W,H,fill=1,stroke=0)
    c.setFillColor(INK);c.rect(0,H-79,W,79,fill=1,stroke=0)
    c.setFillColor(HexColor('#D7D8CF'));c.setFont('Mono',8.1);c.drawString(LEFT,H-20,'MiG-29A  /  OPERATIONAL CONVERSION')
    c.setFillColor(white);c.setFont('Head',min(23.5,23.5*WIDTH/pdfmetrics.stringWidth(title,'Head',23.5)));c.drawString(LEFT,H-47,title)
    c.setFont('Body',min(9.4,9.4*WIDTH/pdfmetrics.stringWidth(sub,'Body',9.4)));c.setFillColor(HexColor('#D7D8CF'));c.drawString(LEFT,H-65,sub)
    c.setFillColor(RED);c.rect(LEFT,H-82,42,3,fill=1,stroke=0)
    c.setStrokeColor(HexColor('#C3C7C0'));c.setLineWidth(.5);c.line(LEFT,27,W-LEFT,27)
    c.setFillColor(SLATE);c.setFont('Mono',7.6);c.drawString(LEFT,15,'IRON87ITA  /  DCS TRAINING  /  EN v1.1')
    c.drawRightString(W-LEFT,15,f'{page_no:02d} / 08')
    c.bookmarkPage(f'p{page_no}');c.addOutlineEntry(title,f'p{page_no}',level=0)
    return H-99
def box(text,y,tone='red',size=10.7):
    col=RED if tone=='red' else OLIVE
    p=Paragraph(text,ParagraphStyle('box',fontName='Body',fontSize=size,leading=size*1.29,textColor=INK))
    _,h=p.wrap(WIDTH-24,1000);bh=h+19
    assert y-bh>=31,('Box overflow',page_no,text[:80],y,bh)
    c.setFillColor(HexColor('#E8E1D6') if tone=='red' else HexColor('#E4E7DE'));c.rect(LEFT,y-bh,WIDTH,bh,fill=1,stroke=0)
    c.setFillColor(col);c.rect(LEFT,y-bh,3,bh,fill=1,stroke=0);p.drawOn(c,LEFT+12,y-10-h)
    return y-bh-10
def table(rows,widths,y,font=10.8,header_row=True,pad=4):
    prepared=[]
    for ri,row in enumerate(rows):
        prepared.append([Paragraph(str(v),ParagraphStyle('cell',fontName='Bold' if ri==0 and header_row else 'Body',fontSize=font,leading=font*1.24,textColor=white if ri==0 and header_row else INK)) for v in row])
    t=Table(prepared,colWidths=widths,hAlign='LEFT')
    commands=[('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),7),('RIGHTPADDING',(0,0),(-1,-1),7),('TOPPADDING',(0,0),(-1,-1),pad),('BOTTOMPADDING',(0,0),(-1,-1),pad),('LINEBELOW',(0,0),(-1,-1),.35,HexColor('#C7CCC4'))]
    if header_row: commands+=[('BACKGROUND',(0,0),(-1,0),INK)]
    t.setStyle(TableStyle(commands));_,h=t.wrap(WIDTH,1000);assert y-h>=31,('Table overflow',page_no,y,h);t.drawOn(c,LEFT,y-h)
    return y-h-12
def card(num,title,meta,body,y):
    c.setFillColor(RED);c.roundRect(LEFT,y-18,27,18,2,fill=1,stroke=0)
    c.setFillColor(white);c.setFont('MonoB',11);c.drawCentredString(LEFT+13.5,y-13,str(num).zfill(2))
    p=Paragraph(title,ParagraphStyle('card',fontName='Head',fontSize=14.1,leading=15.2,textColor=INK));_,th=p.wrap(WIDTH-37,1000);p.drawOn(c,LEFT+37,y-th)
    y-=max(th,18)+5
    y=para(meta,y,size=8.8,leading=10.8,color=SLATE,bold=True)-4
    y=para(body,y,size=10.7,leading=13.4)-8
    c.setStrokeColor(HexColor('#CCD0C8'));c.setLineWidth(.5);c.line(LEFT,y+5,W-LEFT,y+5)
    return y
def end():c.showPage()

y=header('OPS','MISSION CARD','KOBULETI  /  HOT START  /  FOUR CLIENT POSITIONS')
y=box('<b>REARM FIRST. START THE EXERCISE AIRBORNE.</b><br/>Air contacts spawn immediately.',y)
steps=[('01','PREPARE','Check fuel, stores, CM and SN-29/DTC.'),('02','DEPART','Complete aircraft checks, obtain clearance.'),('03','ACTIVATE','F10 &gt; MiG-29A TRAINING CAMPAIGN &gt; CAMPAIGN MISSIONS.'),('04','RECOVER','Return, rearm and review the training record.')]
for n,t,b in steps:
    y=para(f'<font color="#A44335"><b>{n}</b></font>  <b>{t}</b>  {b}',y,size=11.2,leading=14.1)-8
y=label('R-862 PRESETS  /  ALL FREQUENCIES AM',y-1)
y=table([['Cockpit CH','Station','MHz'],['0 / 1','Kobuleti','133.000'],['2','Batumi','131.000'],['3','Kutaisi','134.000'],['4','Senaki','132.000'],['5','Flight','124.000']],[81,155,104],y,font=10.6)
y=para('Verify actual cockpit/DTC tuning before ATC calls. No tanker is available. Dynamic targets are not uploaded automatically to the navigator.',y,size=10.4,leading=13.2,color=SLATE)
end()

y=header('AIR','PHASE 1 / AIR DEFENCE','EXERCISES 01-04  /  FOX 1 + FOX 2 ONLY')
y=card(1,'VISUAL FIGHTER ENGAGEMENT','MiG-21bis  |  35 NM  |  12,000 ft / 3,658 m', 'R-60M-only opponents hold fire through the first neutral merge. The trainee also waits until the first pass. Practise visual acquisition, IRST/HMS, R-73 and cannon.',y)
y=card(2,'AIR DEFENCE INTERCEPT','MiG-21bis  |  42 NM  |  18,000 ft / 5,486 m', 'Practise N019 search and acquisition, radar/IRST correlation and positive identification. Reference trainee weapons are R-27R and R-73. No dedicated campaign GCI is added.',y)
y=card(3,'BVR INTERCEPT','MiG-23MLD  |  48 NM  |  22,000 ft / 6,706 m', 'Opponents carry R-24R/R-24T/R-60M. Practise R-27R employment and maintain the required radar support. Manage any transition to close combat and R-73.',y)
y=card(4,'HIGH-ALTITUDE INTERCEPT','MiG-25PD / MiG-21bis  |  55 NM  |  30,000 ft / 9,144 m', 'Practise radar elevation control, geometry, energy and endurance. A solo pilot faces one MiG-25PD. Additional pilots add contacts from the original alternating mix.',y)
y=para('Ranges and altitudes above are initial contact spawn conditions. Opposition: one fighter per active BLUE pilot, maximum four.',y,size=9.6,leading=12.1,color=SLATE)
end()

y=header('GROUND','PHASE 2 / GROUND ATTACK','EXERCISES 05-07  /  UNGUIDED WEAPONS')
y=card(5,'LOGISTICS CONVOY STRIKE','7 vehicles  |  Random designated ground range', 'Attack the logistics group using module-compatible FAB/OFAB bombs or S-8 rockets. Obtain observer coordinates and acquire targets visually. This exercise does not provide laser-guided weapons.',y)
y=card(6,'ARMOURED INTERDICTION','7 vehicles  |  Armour / mechanised force with ZSU-23-4', 'Prepare an appropriate unguided loadout before departure. Assess the anti-aircraft threat and limit target-area exposure. SPO-15LM is an awareness aid; combine it with visual search.',y)
y=card(7,'SHORT-RANGE AIR DEFENCE ATTACK','6 vehicles  |  Strela-10M3 + ZSU-23-4', 'Conduct a conventional attack on the SHORAD position. No anti-radiation missile is provided. Account for IR threats, countermeasures and disengagement before committing to another pass.',y)
y=box('<b>OBSERVER, NOT LASER GUIDANCE</b><br/>F10 supplies target coordinates. The retained 1688 laser is an external reference; the Fulcrum cannot track that spot or use it to guide these weapons.',y,size=10.6)
end()

y=header('ADVANCED','PHASE 3 / EVALUATION','EXERCISES 08-09  /  MIXED OBJECTIVES')
y=card(8,'COMBINED ARMS EXERCISE','MiG-23MLD: 50 NM / 20,000 ft (6,096 m)  |  7 ground targets', 'A mechanised force with AAA is covered by fighters. Prepare a compatible mixed loadout, such as R-73 and FAB/OFAB bombs. In multiplayer, agree task priorities and roles before activation.',y)
y=card(9,'FINAL OPERATIONAL EVALUATION','Fighters: 58 NM / 24,000 ft (7,315 m)  |  9 ground targets', 'Complete both air and ground objectives. One active pilot spawns MiG-21bis; the next three add MiG-23MLD, MiG-25PD and MiG-29A in that order. Ground strength remains fixed.',y)
y=label('SORTIE PLANNING',y)
for text in ['Agree the mixed loadout and flight roles before activation.','Monitor fuel, stores and the remaining ground threat.','Recover and rearm as needed; complete residual targets, then return to Kobuleti.']:
    y=para('• '+text,y,size=11.2,leading=14.1)-7
y=box('<b>COMPLETION</b><br/>Every assigned air and ground objective must be destroyed. An incomplete spawn suspends credit: restart the selected exercise.',y,tone='olive')
end()

y=header('SYSTEMS','AIR COMBAT REFERENCE','TASK REMINDERS  /  CONSULT THE MODULE MANUAL FOR SWITCHING')
for title,text in [
 ('N019 RADAR','Select suitable search/acquisition modes. Check elevation and target association; identify before firing.'),
 ('IRST + HMS','Use IRST/HMS for close-combat acquisition and R-73 cueing. Confirm seeker acquisition before release.'),
 ('R-27R / FOX 1','Semi-active radar homing. Maintain the required radar support; this is not a fire-and-forget weapon.'),
 ('R-73 / FOX 2','Confirm the intended target and seeker acquisition. In Exercise 01, wait until the first neutral pass.'),
 ('GSh-30-1','30 mm cannon. Use controlled employment; observe module limitations and monitor remaining ammunition.'),
 ('SPO-15LM','Use the RWR for awareness. No warning does not mean no threat: IR weapons may give no radar warning.')]:
    y=para(title,y,size=11.5,leading=14,bold=True)-4
    y=para(text,y,size=11.2,leading=14.2)-12
y=para('No FOX 3 and no R-27ER/ET in this programme. Rearming choices are not script-locked; comply with the exercise rules.',y,size=10.3,leading=13,color=SLATE)
end()

y=header('STORES','LOADOUT & NAVIGATION','FULL FIDELITY NATIVE STORES  /  R-862 + SN-29')
y=label('INITIAL AIR-TO-AIR CONFIGURATION',y)
rows=[['ME slot','1','2','3','4','5','6','7'],['Store','-','R-73','R-27R','Tank','R-27R','R-73','-']]
y=table(rows,[53]+[41]*7,y,font=9.1)
y=para('<b>2 R-27R + 2 R-73 + centreline tank.</b><br/>3376 kg internal fuel; 30 chaff and 30 flare; GSh-30-1. Slot numbers above are Mission Editor indices.',y,size=11.3,leading=14.7)-14
y=label('REARM FOR THE TASK',y)
for title,text in [('VISUAL / 01','R-73-only rearming supports a comparable visual exercise. Wait until the first neutral merge.'),('GROUND / 05-07','Select compatible FAB/OFAB bombs or S-8 rockets. Follow module rearming and delivery procedures.'),('COMBINED / 08-09','Retain air-to-air capability with unguided ground stores. Recover and rearm if required.')]:
    y=para('<b>'+title+'</b><br/>'+text,y,size=11.1,leading=14.1)-12
y=box('<b>NAVIGATION CHECK</b><br/>Verify SN-29/DTC data and the recovery airfield. Dynamic targets are not uploaded: use live F10 coordinates.',y,tone='olive',size=10.7)
end()

y=header('RANGES','TRAINING RANGE INDEX','SCHEMATIC  /  LOCAL DCS GRID  /  NOT A TERRAIN CHART')
base=next(n.value for _,n in walk(mtree) if isinstance(n.value,dict) and n.value.get('type')=='MiG-29 Fulcrum' and n.value.get('skill')=='Client')
bx,by=base['x'],base['y']
map_x,map_y,map_w,map_h=LEFT+14,y-175,305,170
scale=2.75
def mp(e,n):return map_x+e*scale,map_y+n*scale
c.setFillColor(HexColor('#E7E9E1'));c.rect(map_x,map_y,map_w,map_h,fill=1,stroke=0)
for e in range(0,91,15):
    x0,_=mp(e,0);c.setStrokeColor(HexColor('#CDD3C8'));c.setLineWidth(.35);c.line(x0,map_y,x0,map_y+map_h)
    c.setFont('Mono',7);c.setFillColor(SLATE);c.drawCentredString(x0,map_y-10,str(e))
for n in range(0,61,15):
    _,y0=mp(0,n);c.setStrokeColor(HexColor('#CDD3C8'));c.line(map_x,y0,map_x+map_w,y0)
    c.setFont('Mono',7);c.setFillColor(SLATE);c.drawRightString(map_x-4,y0-2,str(n))
c.setFont('MonoB',7.3);c.setFillColor(SLATE);c.drawString(map_x,map_y+map_h+5,'N GRID / km');c.drawRightString(map_x+map_w,map_y-20,'E GRID / km')
kx,ky=mp(0,0);c.setFillColor(INK);c.circle(kx,ky,3,fill=1,stroke=0);c.setFont('MonoB',8);c.drawString(kx+8,ky+6,'KOBULETI / REF')
offsets=[(10,-3),(-27,-13),(9,-10),(10,-4),(-28,-13),(-14,10),(-28,0),(10,7)]
range_rows=[['Alias','Editor zone','Range from ref']]
for z in zones:
    rx,ry=mp((z['y']-by)/1000,(z['x']-bx)/1000)
    c.setStrokeColor(HexColor('#B6C1B6'));c.setLineWidth(.4);c.line(kx,ky,rx,ry)
for i,z in enumerate(zones):
    e=(z['y']-by)/1000;n=(z['x']-bx)/1000;px,py=mp(e,n)
    c.setStrokeColor(RED);c.setLineWidth(.8);c.circle(px,py,z['radius']/1000*scale,fill=0,stroke=1)
    c.setFillColor(RED);c.circle(px,py,2,fill=1,stroke=0)
    dx,dy=offsets[i];c.setStrokeColor(SLATE);c.setLineWidth(.5);c.line(px,py,px+dx,py+dy)
    c.setFillColor(HexColor('#E7E9E1'));c.rect(px+dx-1,py+dy-2,13,10,fill=1,stroke=0)
    c.setFillColor(INK);c.setFont('MonoB',8.2);c.drawString(px+dx,py+dy,f'G{i}')
    distance=__import__("math").hypot(e,n);suffix='(no suffix)' if i==0 else f'-{i}'
    range_rows.append([f'G{i}',f'GROUND {suffix}',f'{distance:.1f} km / {distance/1.852:.1f} NM'])
c.setFillColor(HexColor('#E7E9E1'));c.rect(kx+7,ky+4,76,12,fill=1,stroke=0)
c.setFillColor(INK);c.setFont('MonoB',8);c.drawString(kx+8,ky+6,'KOBULETI / REF')
y=map_y-25
y=table(range_rows,[49,138,153],y,font=8.8,pad=2)
y=para('G0-G7 are aliases for <b>SPAWN ZONE GROUND</b> and suffixes. Radius: 457.2 m. Distances from Client 01, not routes. Use live F10 MGRS for actual units.',y,size=9.4,leading=12,color=SLATE)
end()

y=header('RECORDS','F10 & TRAINING RECORD','MENU GUIDE  /  COMPLETION  /  PROGRESS')
y=label('F10 > MiG-29A TRAINING CAMPAIGN',y)
menurows=[['CAMPAIGN MISSIONS','Choose an exercise or START NEXT IN SEQUENCE.'],['FREE TRAINING - AIR / GROUND','Random/by-type contacts or ground groups.'],['GROUND OBSERVER','Coordinates (no laser guidance); select next target.'],['ACTIVE MISSION BRIEF','Repeat tasking and remaining objectives.'],['CAMPAIGN STATUS / MY TRAINING RECORD','View progress, score and persistence.'],['RESET TRAINING RANGE','Remove the active exercise.']]
y=table(menurows,[134,206],y,font=9.4,header_row=False,pad=3)
y=para('<b>SCORING</b>  Air kill +25 | Ground kill +10<br/>First completion of each exercise +100.',y,size=10.9,leading=14)-11
y=para('<b>SESSION ONLY</b>: progress ends when the mission closes.<br/><b>DISK SAVE ACTIVE</b>: saved between sessions when host io/lfs is already available.',y,size=10.2,leading=13)-9
y=para('F10 menus are group-shared. Queries/START NEXT use the first active player; records store player names.',y,size=9.8,leading=12.4,color=SLATE)-8
y=para('Reference: official module manual and local DCS data. Campaign aid, not a cockpit checklist or qualification syllabus.',y,size=9.2,leading=11.5,color=SLATE)
c.linkURL('https://www.digitalcombatsimulator.com/en/shop/modules/fulcrum/',(LEFT,31,W-LEFT,48),relative=0,thickness=0)
end();assert page_no==8;c.save()
(WORK/'layout.json').write_text(json.dumps(layout,indent=2),encoding='utf-8')

renderer=shutil.which(args.pdftoppm) or args.pdftoppm
subprocess.run([str(renderer),'-png','-r','288',str(PDF),str(WORK/'kneeboard')],check=True,capture_output=True)
pages=sorted(WORK.glob('kneeboard-*.png'))
assert len(pages)==8,len(pages)
for page in pages:
    with Image.open(page) as im:assert im.size==(1536,2048),(page,im.size)
# Contact sheet is a QA artifact made from the authored kneeboard, not an edit of the cover.
sheet=Image.new('RGB',(1536,1056),'#25323b')
for i,p in enumerate(pages):
    with Image.open(p) as im:
        im.thumbnail((366,488));sheet.paste(im,((i%4)*384+9,(i//4)*528+9))
sheet.save(WORK/'kneeboard_contact_sheet.png')

print(PDF)
