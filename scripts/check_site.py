#!/usr/bin/env python3
"""Site checks: every HTML page parses, has a <title> and lang, and every local link/asset exists."""
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

SITE = Path(__file__).resolve().parent.parent / "site"


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs, self.has_title, self.lang, self.csp = [], False, False, ""

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "title":
            self.has_title = True
        if tag == "html" and a.get("lang"):
            self.lang = True
        if tag == "meta" and (a.get("http-equiv") or "").lower() == "content-security-policy":
            self.csp = a.get("content") or ""
        for key in ("href", "src"):
            if a.get(key):
                self.refs.append(a[key])


errors = []
pages = sorted(SITE.rglob("*.html"))
if not pages:
    errors.append("no HTML pages in site/")
for page in pages:
    p = Page()
    p.feed(page.read_text(encoding="utf-8"))
    rel = page.relative_to(SITE)
    if not p.has_title:
        errors.append(f"{rel}: missing <title>")
    if not p.lang:
        errors.append(f"{rel}: <html> missing lang attribute")
    # Every page keeps a strict Content-Security-Policy: no inline scripts, nothing from other sites
    # except the GitHub API (download links).
    if "default-src 'none'" not in p.csp or "'unsafe-inline'" in p.csp or "script-src 'self'" not in p.csp:
        errors.append(f"{rel}: missing or weakened Content-Security-Policy meta tag")
    for ref in p.refs:
        u = urlparse(ref)
        if u.scheme or ref.startswith(("#", "mailto:", "//")):
            continue
        target = (page.parent / u.path).resolve() if not u.path.startswith("/") else (SITE / u.path.lstrip("/")).resolve()
        if u.path and not target.exists():
            errors.append(f"{rel}: broken link -> {ref}")

for e in errors:
    print("FAIL", e)
print(f"checked {len(pages)} pages, {len(errors)} problems")
sys.exit(1 if errors else 0)
