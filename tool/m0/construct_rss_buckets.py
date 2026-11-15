#!/usr/bin/env python3
"""Construct the offline RSS buckets (05 §1.2) from a captured real template:
missing_fields / giant / malformed / weird_dates.

Real template is taken from test/fixtures/rss/standard (first file in manifest).
Deterministic given the template: fixed seed, fixed timestamps.

G7 coverage requirements:
- itunes:duration both legal forms (HH:MM:SS and plain seconds)
- missing itunes:duration / itunes:image / pubDate / itunes:author
- pubDate RFC822 old formats / timezone abbreviations / future times
"""
import json
import os
import random
import sys
from xml.etree import ElementTree as ET

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RSS = os.path.join(REPO, 'test', 'fixtures', 'rss')

ITUNES_NS = 'http://www.itunes.com/dtds/podcast-1.0.dtd'
ET.register_namespace('itunes', ITUNES_NS)

manifest = json.load(open(os.path.join(RSS, 'manifest.json')))
template_file = manifest['live']['standard'][0]['file']
template_url = manifest['live']['standard'][0]['url']
template_path = os.path.join(RSS, 'standard', template_file)
tree = ET.parse(template_path)
root = tree.getroot()
channel = root if root.tag.endswith('channel') else root.find('.//channel')
items = channel.findall('item')
print(f'template: {template_file} ({len(items)} items)')

rng = random.Random(20260922)

def item_proto(i):
    """Fabricate a deterministic item based on template item i."""
    src = items[i % len(items)]
    def txt(tag, ns=None):
        el = src.find(f'itunes:{tag}', {'itunes': ITUNES_NS}) if ns else src.find(tag)
        return el.text if el is not None and el.text else None
    return {
        'title': txt('title') or f'Episode {i}',
        'link': txt('link') or f'https://example.com/ep{i}',
        'pubDate': txt('pubDate'),
        'description': txt('description') or f'Description {i}',
        'itunes_duration': txt('duration', ns=True),
        'itunes_author': txt('author', ns=True),
        'enclosure_url': (src.find('enclosure').get('url')
                          if src.find('enclosure') is not None else f'https://audio.example.com/ep{i}.mp3'),
        'enclosure_type': 'audio/mpeg',
        'enclosure_length': str(rng.randrange(20_000_000, 90_000_000)),
        'itunes_image': (src.find('itunes:image', {'itunes': ITUNES_NS}).get('href')
                         if src.find('itunes:image', {'itunes': ITUNES_NS}) is not None else None),
    }

def write_item(chan, p, *, duration=None, pub_date=None, author=None, image=None,
               description=None, title=None):
    it = ET.SubElement(chan, 'item')
    ET.SubElement(it, 'title').text = title or p['title']
    ET.SubElement(it, 'link').text = p['link']
    if pub_date is not False:
        ET.SubElement(it, 'pubDate').text = pub_date if pub_date is not None else p['pubDate']
    desc = description if description is not None else p['description']
    if desc is not False:
        ET.SubElement(it, 'description').text = desc
    if duration is not False:
        val = duration if duration is not None else p['itunes_duration']
        if val is not None:
            ET.SubElement(it, f'{{{ITUNES_NS}}}duration').text = val
    if author is not False:
        val = author if author is not None else p['itunes_author']
        if val is not None:
            ET.SubElement(it, f'{{{ITUNES_NS}}}author').text = val
    if image is not False:
        val = image if image is not None else p['itunes_image']
        if val is not None:
            ET.SubElement(it, f'{{{ITUNES_NS}}}image', {'href': val})
    enc = ET.SubElement(it, 'enclosure')
    enc.set('url', p['enclosure_url'])
    enc.set('type', p['enclosure_type'])
    enc.set('length', p['enclosure_length'])
    return it

def new_feed(title_suffix):
    r = ET.Element('rss', {'version': '2.0'})
    ch = ET.SubElement(r, 'channel')
    ET.SubElement(ch, 'title').text = (channel.findtext('title') or 'Template') + title_suffix
    ET.SubElement(ch, 'link').text = channel.findtext('link') or 'https://example.com/'
    ET.SubElement(ch, 'description').text = channel.findtext('description') or ''
    img = channel.find('image')
    if img is not None:
        ch.append(img)
    ti = channel.find('itunes:image', {'itunes': ITUNES_NS})
    if ti is not None:
        ch.append(ti)
    return r, ch

def save(bucket, name, r, note):
    d = os.path.join(RSS, bucket)
    os.makedirs(d, exist_ok=True)
    ET.ElementTree(r).write(os.path.join(d, f'{name}.xml'), encoding='utf-8', xml_declaration=True)
    recs = []
    mf = os.path.join(d, 'manifest.json')
    if os.path.exists(mf):
        recs = json.load(open(mf))
    recs.append(note)
    json.dump(recs, open(mf, 'w'), ensure_ascii=False, indent=1)

# --- missing_fields: four variants, one field family missing each ---
r, ch = new_feed(' (no duration)')
for i in range(12):
    write_item(ch, item_proto(i), duration=False)
save('missing_fields', 'no_duration', r, {
    'file': 'no_duration.xml', 'missing': ['itunes:duration'], 'items': 12,
    'url': 'constructed:' + template_url, 'bucket': 'missing_fields'})

r, ch = new_feed(' (no image)')
for i in range(12):
    write_item(ch, item_proto(i), image=False)
save('missing_fields', 'no_image', r, {
    'file': 'no_image.xml', 'missing': ['itunes:image'], 'items': 12,
    'url': 'constructed:' + template_url, 'bucket': 'missing_fields'})

r, ch = new_feed(' (no pubDate)')
for i in range(12):
    write_item(ch, item_proto(i), pub_date=False)
save('missing_fields', 'no_pubdate', r, {
    'file': 'no_pubdate.xml', 'missing': ['pubDate'], 'items': 12,
    'url': 'constructed:' + template_url, 'bucket': 'missing_fields'})

r, ch = new_feed(' (no author)')
for i in range(12):
    write_item(ch, item_proto(i), author=False)
save('missing_fields', 'no_author', r, {
    'file': 'no_author.xml', 'missing': ['itunes:author'], 'items': 12,
    'url': 'constructed:' + template_url, 'bucket': 'missing_fields'})

# duration formats: HH:MM:SS vs plain seconds (G7 assertion note)
r, ch = new_feed(' (mixed duration formats)')
for i in range(12):
    d = '01:02:03' if i % 2 == 0 else str(3723 + i)
    write_item(ch, item_proto(i), duration=d)
save('missing_fields', 'mixed_duration_formats', r, {
    'file': 'mixed_duration_formats.xml', 'note': 'HH:MM:SS and plain-seconds durations alternate',
    'items': 12, 'url': 'constructed:' + template_url, 'bucket': 'missing_fields'})

# --- giant: 1200 items + one item with >1MB description ---
r, ch = new_feed(' (giant)')
big = 'x' * (1_050_000)
for i in range(1200):
    write_item(ch, item_proto(i), description=(big if i == 600 else None))
save('giant', 'giant_1200_items', r, {
    'file': 'giant_1200_items.xml', 'items': 1200,
    'note': 'item[600].description is >1MB', 'url': 'constructed:' + template_url,
    'bucket': 'giant'})

# --- malformed: truncated XML / non-XML (HTML error page) / BOM prefix ---
src = open(template_path, 'rb').read()
d = os.path.join(RSS, 'malformed')
os.makedirs(d, exist_ok=True)
truncated = src[:int(len(src) * 0.4)]
open(os.path.join(d, 'truncated.xml'), 'wb').write(truncated)
html_page = (b'<!DOCTYPE html><html><head><title>503 Service Unavailable</title></head>'
             b'<body><h1>503 Service Temporarily Unavailable</h1>'
             b'<p>The server is temporarily unable to service your request...</p></body></html>')
open(os.path.join(d, 'html_error_page.xml'), 'wb').write(html_page)
bommed = b'\xef\xbb\xbf' + src
open(os.path.join(d, 'bom_prefixed.xml'), 'wb').write(bommed)
json.dump([
    {'file': 'truncated.xml', 'note': 'first 40% of a real feed, cut mid-tag'},
    {'file': 'html_error_page.xml', 'note': 'HTML 503 page served with 200 by real hosts'},
    {'file': 'bom_prefixed.xml', 'note': 'UTF-8 BOM prepended to a real feed'},
], open(os.path.join(d, 'manifest.json'), 'w'), ensure_ascii=False, indent=1)

# --- weird_dates: RFC822 variants, TZ abbreviations, future ---
r, ch = new_feed(' (weird dates)')
dates = [
    'Mon, 01 Jan 1990 00:00:00 GMT',       # very old RFC822
    'Tue, 15 Mar 1994 12:30:45 +0000',    # old, numeric offset
    'Wed, 02 Feb 2022 09:15:00 EST',      # TZ abbreviation
    'Thu, 03 Mar 2022 09:15:00 CST',      # ambiguous abbreviation
    'Fri, 01 Apr 2022 09:15:00 +0800',    # CN offset
    'Sat, 31 Dec 2033 23:59:59 GMT',      # far future
    'Sun, 22 Sep 2030 10:00:00 Z',        # future with Z suffix
    '22 Sep 2026 10:00:00 GMT',            # missing weekday (legal RFC822)
    'Mon, 22 Sep 2026 10:00:00 UT',        # UT abbreviation
    'not a date at all',                    # garbage
    '',                                     # empty
    'Mon, 29 Feb 2027 10:00:00 GMT',       # invalid calendar date (2027 not leap)
]
for i, dt in enumerate(dates):
    write_item(ch, item_proto(i), pub_date=dt)
save('weird_dates', 'weird_pubdates', r, {
    'file': 'weird_pubdates.xml', 'items': len(dates), 'dates': dates,
    'url': 'constructed:' + template_url, 'bucket': 'weird_dates'})

print('constructed buckets written: missing_fields(5) giant(1) malformed(3) weird_dates(1)')
