"""Validate archive integrity, FF clients, resource references and kneeboard sizes."""
import pathlib,argparse,zipfile,struct,hashlib
from lua_data import Parser,walk
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('mission',nargs='?',type=pathlib.Path,default=ROOT/'dist/MiG29A_FF_Operational_Conversion_EN_v1.1.miz')
a=p.parse_args()
with zipfile.ZipFile(a.mission) as z:
    assert z.testzip() is None,'Archive CRC failure'
    m=Parser(z.read('mission').decode('utf-8-sig')).assignment()
    clients=[n.value for _,n in walk(m) if isinstance(n.value,dict) and n.value.get('skill') in ['Client','Player']]
    assert len(clients)==4 and all(u['type']=='MiG-29 Fulcrum' for u in clients),'Expected four FF Client aircraft'
    for name in ['warehouses','options','l10n/DEFAULT/dictionary','l10n/DEFAULT/mapResource']:Parser(z.read(name).decode('utf-8-sig')).assignment()
    resources=Parser(z.read('l10n/DEFAULT/mapResource').decode('utf-8-sig')).assignment().value
    for key,name in resources.items():assert 'l10n/DEFAULT/'+name in z.namelist(),key
    for key in ['pictureFileNameB','pictureFileNameR','pictureFileNameN']:
        for image_key in m.value[key].values():assert image_key in resources,image_key
    pages=[n for n in z.namelist() if n.startswith('KNEEBOARD/IMAGES/') and n.endswith('.png')]
    assert len(pages)==8,'Expected eight kneeboard cards'
    for name in pages:
        b=z.read(name);assert b[:8]==bytes([137,80,78,71,13,10,26,10])
        assert struct.unpack('>II',b[16:24])==(1536,2048),name
    script=z.read('l10n/DEFAULT/Dynamic_Training.lua').decode('utf-8')
    assert 'spawnFailed' in script and 'MiG29ATrainingFF' in script
    assert 'KC135MPRS' not in script and 'Super 530' not in script and 'Magic I' not in script
    assert len(m.value['triggers']['zones'])==8
print('PASS: archive, four FF clients, resource links, eight 1536x2048 cards, campaign invariants')
print('SHA256:',hashlib.sha256(a.mission.read_bytes()).hexdigest())
