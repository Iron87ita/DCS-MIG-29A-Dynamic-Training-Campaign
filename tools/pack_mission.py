"""Rebuild the campaign from the editable mission tree and artwork."""
import pathlib, argparse, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=pathlib.Path,default=ROOT/'dist/rebuilt.miz')
args=p.parse_args();args.output.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(args.output,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for path in sorted((ROOT/'mission').rglob('*')):
        if path.is_file():z.write(path,path.relative_to(ROOT/'mission').as_posix())
    z.write(ROOT/'assets/cover.png','l10n/DEFAULT/MiG29A_Campaign_Cover_EN.png')
    for path in sorted((ROOT/'assets/kneeboard').glob('*.png')):z.write(path,'KNEEBOARD/IMAGES/'+path.name)
print(args.output)
