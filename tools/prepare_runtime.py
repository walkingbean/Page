"""Bundle the unchanged pinned Dialogic sources and their imported resources.
Run after a successful Godot 4.7.1 editor import, before platform exports.
"""
from pathlib import Path
import re,zipfile,json,hashlib
P=Path(__file__).resolve().parents[1]
def main():
 cache=P/'.godot/global_script_class_cache.cfg'
 if not cache.is_file():raise SystemExit('Import the project with Godot 4.7.1 first.')
 text=cache.read_text(); entries=re.findall(r'\{[^{}]*\}',text,re.S)
 entries=[x for x in entries if '"path": "res://addons/dialogic/' in x]
 if not entries:raise SystemExit('Pinned Dialogic class cache is empty.')
 files={}
 for p in (P/'addons/dialogic').rglob('*'):
  if not p.is_file() or '.git' in p.parts:continue
  files[p.relative_to(P).as_posix()]=p
  if p.suffix=='.import':
   for item in re.findall(r'"res://([^"\n]+)"',p.read_text()):
    q=P/item
    if q.is_file():files[item]=q
 out=P/'runtime/native_runtime.zip';out.parent.mkdir(exist_ok=True)
 with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
  for name,path in sorted(files.items()):z.write(path,name)
  z.write(P/'preview/project_entry.gd','__page_preview/entry.gd')
  z.writestr('.godot/global_script_class_cache.cfg','list=Array[Dictionary](['+',\n'.join(entries)+'])\n')
  z.writestr('native_dependency_manifest.json',json.dumps({name:hashlib.sha256(path.read_bytes()).hexdigest() for name,path in files.items()},sort_keys=True))
 print(json.dumps({'runtime':str(out),'files':len(files),'classes':len(entries),'bytes':out.stat().st_size,'sha256':hashlib.sha256(out.read_bytes()).hexdigest()}))
if __name__=='__main__':main()
