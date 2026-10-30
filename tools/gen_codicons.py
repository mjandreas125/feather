import csv, re, sys, os, shutil

pkg, out_dart, out_font = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(os.path.dirname(out_font), exist_ok=True)
shutil.copyfile(os.path.join(pkg, 'dist', 'codicon.ttf'), out_font)

rows = []
with open(os.path.join(pkg, 'dist', 'codicon.csv'), encoding='utf-8') as f:
    for r in csv.DictReader(f):
        name = r.get('short_name') or r.get('name')
        code = r.get('unicode') or r.get('code')
        if not name or not code:
            continue
        rows.append((name.strip(), int(code.strip().replace('\\', '').replace('U+', ''), 16)))

reserved = {'import', 'export', 'class', 'new', 'switch', 'case', 'default', 'is', 'in', 'as', 'if', 'else',
            'for', 'do', 'while', 'return', 'library', 'part', 'final', 'const', 'var', 'void', 'null', 'true',
            'false', 'this', 'super', 'with', 'try', 'catch', 'throw', 'get', 'set', 'enum', 'extends'}

def ident(n):
    parts = re.split(r'[^a-zA-Z0-9]+', n)
    s = parts[0].lower() + ''.join(p[:1].upper() + p[1:] for p in parts[1:])
    if s[0].isdigit():
        s = 'i' + s
    if s in reserved:
        s += 'Icon'
    return s

seen = set()
lines = []
for name, code in rows:
    i = ident(name)
    if i in seen:
        continue
    seen.add(i)
    lines.append(f"  static const IconData {i} = IconData(0x{code:x}, fontFamily: _f);")

with open(out_dart, 'w', encoding='utf-8', newline='\n') as f:
    f.write("// GENERATED from @vscode/codicons (CC BY 4.0, Microsoft). Do not edit by hand.\n")
    f.write("// Regenerate: tools/gen_codicons.py\n")
    f.write("import 'package:flutter/widgets.dart';\n\n")
    f.write("/// The VS Code icon set (Codicons), so the app looks like the editor people know.\n")
    f.write("class Codicons {\n  Codicons._();\n  static const _f = 'codicon';\n")
    f.write('\n'.join(lines))
    f.write('\n}\n')
print(len(lines), 'icons')
