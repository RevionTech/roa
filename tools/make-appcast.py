#!/usr/bin/env python3
"""Create the latest-only feed; publish-update.sh adds its EdDSA signature."""
import datetime
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parents[1]
package = Path(sys.argv[1])
signature = sys.argv[2]
with (root / 'Resources/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
version = info['CFBundleShortVersionString']
assert re.fullmatch(r'\d+\.\d+\.\d+', version)
assert package.name == f'ROA-{version}-universal.pkg'
namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', namespace)
feed = ET.Element('rss', version='2.0')
channel = ET.SubElement(feed, 'channel')
ET.SubElement(channel, 'title').text = 'ROA Updates'
ET.SubElement(channel, 'link').text = 'https://github.com/RevionTech/roa'
ET.SubElement(channel, 'description').text = 'Signed ROA updates by Revion Tech.'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'ROA {version}'
ET.SubElement(item, 'pubDate').text = datetime.datetime.now(datetime.timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')
ET.SubElement(item, f'{{{namespace}}}version').text = info['CFBundleVersion']
ET.SubElement(item, f'{{{namespace}}}shortVersionString').text = version
ET.SubElement(item, f'{{{namespace}}}minimumSystemVersion').text = '13.0.0'
ET.SubElement(item, 'description').text = 'Update ROA, its CLI and power service together. Installation requires administrator authorization and starts ROA OFF.'
ET.SubElement(item, 'enclosure', {
    'url': f'https://github.com/RevionTech/roa/releases/download/v{version}/{package.name}',
    'length': str(package.stat().st_size), 'type': 'application/octet-stream',
    f'{{{namespace}}}edSignature': signature, f'{{{namespace}}}installationType': 'package'})
ET.indent(feed)
(root / 'updates').mkdir(exist_ok=True)
ET.ElementTree(feed).write(root / 'updates/appcast.xml', encoding='utf-8', xml_declaration=True)
