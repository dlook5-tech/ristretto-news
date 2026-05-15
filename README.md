# Ristretto News

Sibling A/B test of eXpressO News. Built from a Grok-authored "improved" zip
(2026-05-14) — minimal `parse_grok.py`, single `curation.py`, simple frontend.
Deployed in parallel to https://expresso-news.netlify.app to compare stability
over one week.

- Live site: https://ristretto-news.netlify.app
- Source: this repo
- Cron: every 4 hours via GitHub Actions (`.github/workflows/cron.yml`)
- Curation logic: pure-views + 23-hour velocity hold (see `curation.py`)
