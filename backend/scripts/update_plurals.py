import json
import os

lang_dir = os.path.join("mobile", "flutter_app", "assets", "lang")
files = {"en": "en.json", "tr": "tr.json", "de": "de.json"}

plurals = {
    "en": {
        "book_count_one": "1 book",
        "book_count_other": "{count} books",
        "catalog_count_one": "There is 1 book in the catalog",
        "catalog_count_other": "There are {count} books in the catalog"
    },
    "tr": {
        "book_count_one": "1 kitap",
        "book_count_other": "{count} kitap",
        "catalog_count_one": "Katalogda 1 kitap var",
        "catalog_count_other": "Katalogda {count} kitap var"
    },
    "de": {
        "book_count_one": "1 Buch",
        "book_count_other": "{count} Bücher",
        "catalog_count_one": "1 Buch im Katalog",
        "catalog_count_other": "{count} Bücher im Katalog"
    }
}

for lang, filename in files.items():
    filepath = os.path.join(lang_dir, filename)
    with open(filepath, 'r', encoding='utf-8') as f:
        data = json.load(f)

    data.update(plurals[lang])

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

print("Localization files updated with plurals.")
