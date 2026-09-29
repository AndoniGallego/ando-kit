#!/usr/bin/env python3
"""Busqueda por palabras clave (BM25 simple) en los CSV de data/. Stdlib pura, solo lee, salida a stdout.

Uso: python search.py "<consulta>" [--domain style|color|typography|ux|product|reasoning|chart|motion|svelte|vue|html] [-n 3]
Sin --domain busca en todos y muestra el mejor de cada uno.
"""
import argparse
import csv
import math
import re
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"

# dominio -> (archivo, columnas a mostrar)
DOMAINS = {
    "style": ("styles.csv", ["Style Category", "Type", "Keywords", "Primary Colors", "Secondary Colors", "Best For", "Do Not Use For", "Accessibility", "Effects & Animation", "CSS/Technical Keywords", "Design System Variables"]),
    "color": ("colors.csv", ["Product Type", "Primary", "On Primary", "Secondary", "Accent", "Background", "Foreground", "Card", "Muted", "Border", "Destructive", "Ring", "Notes"]),
    "typography": ("typography.csv", ["Font Pairing Name", "Category", "Heading Font", "Body Font", "Mood/Style Keywords", "Best For", "CSS Import", "Notes"]),
    "ux": ("ux-guidelines.csv", ["Category", "Issue", "Platform", "Description", "Do", "Don't", "Severity"]),
    "product": ("products.csv", ["Product Type", "Keywords", "Primary Style Recommendation", "Secondary Styles", "Dashboard Style (if applicable)", "Color Palette Focus", "Key Considerations"]),
    "reasoning": ("ui-reasoning.csv", ["UI_Category", "Recommended_Pattern", "Style_Priority", "Color_Mood", "Typography_Mood", "Key_Effects", "Decision_Rules", "Anti_Patterns"]),
    "chart": ("charts.csv", ["Data Type", "Best Chart Type", "Secondary Options", "When to Use", "When NOT to Use", "Color Guidance", "Accessibility Notes", "A11y Fallback", "Library Recommendation"]),
    "motion": ("motion.csv", ["Category", "Intensity Tier", "Trigger", "Duration", "Easing", "GSAP Snippet", "Do", "Don't"]),
    "svelte": ("stacks/svelte.csv", ["Category", "Guideline", "Description", "Do", "Don't", "Code Good", "Severity"]),
    "vue": ("stacks/vue.csv", ["Category", "Guideline", "Description", "Do", "Don't", "Code Good", "Severity"]),
    "html": ("stacks/html-tailwind.csv", ["Category", "Guideline", "Description", "Do", "Don't", "Code Good", "Severity"]),
}
MAX_CELL = 400


def tokens(text):
    return re.findall(r"[a-z0-9áéíóúñ]+", text.lower())


def load(name):
    with open(DATA / name, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def rank(rows, query):
    docs = [tokens(" ".join(v or "" for v in r.values())) for r in rows]
    n = len(docs)
    avg = sum(len(d) for d in docs) / max(n, 1)
    q = set(tokens(query))
    df = {t: sum(1 for d in docs if t in d) for t in q}
    scored = []
    for r, d in zip(rows, docs):
        s = 0.0
        for t in q:
            tf = d.count(t)
            if not tf:
                continue
            idf = math.log((n - df[t] + 0.5) / (df[t] + 0.5) + 1)
            s += idf * tf * 2.5 / (tf + 1.5 * (0.25 + 0.75 * len(d) / avg))
        if s > 0:
            scored.append((s, r))
    scored.sort(key=lambda x: -x[0])
    return scored


def show(domain, rows, query, limit):
    _, cols = DOMAINS[domain]
    for s, r in rank(rows, query)[:limit]:
        print(f"[{domain}] score={s:.2f}")
        for c in cols:
            v = (r.get(c) or "").strip()
            if v:
                print(f"  {c}: {v[:MAX_CELL]}{'...' if len(v) > MAX_CELL else ''}")
        print()


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("query")
    p.add_argument("--domain", choices=sorted(DOMAINS))
    p.add_argument("-n", type=int, default=3)
    a = p.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if a.domain:
        show(a.domain, load(DOMAINS[a.domain][0]), a.query, a.n)
    else:
        for d in DOMAINS:
            show(d, load(DOMAINS[d][0]), a.query, 1)


if __name__ == "__main__":
    main()
