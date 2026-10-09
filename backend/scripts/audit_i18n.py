import json
import os

lang_dir = os.path.join("mobile", "flutter_app", "assets", "lang")
files = {"en": "en.json", "tr": "tr.json", "de": "de.json"}
data = {}

for lang, file in files.items():
    with open(os.path.join(lang_dir, file), 'r', encoding='utf-8') as f:
        data[lang] = json.load(f)

# Find all keys
keys_en = set(data["en"].keys())
keys_tr = set(data["tr"].keys())
keys_de = set(data["de"].keys())

all_keys = keys_en | keys_tr | keys_de

print("Missing in EN:", all_keys - keys_en)
print("Missing in TR:", all_keys - keys_tr)
print("Missing in DE:", all_keys - keys_de)

# Check book pluralizations
for lang in ["en", "tr", "de"]:
    print(f"\n{lang.upper()} 'book_count' or related keys:")
    for k, v in data[lang].items():
        if "book" in k.lower() or "count" in k.lower():
            print(f"  {k}: {v}")
