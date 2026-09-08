#!/usr/bin/env python3
"""Add (or replace) one release in appcast.xml, the Sparkle feed served from the
default branch of the repository.

    scripts/update-appcast.py --version 1.2.3 --build 10203 \
        --url https://github.com/…/MonkeyClaudeUsage-1.2.3.dmg \
        --length 3145728 --signature '…' [--appcast appcast.xml] [--stdout]

Re-running it for a version already in the feed replaces that entry instead of
adding a second one, so an interrupted release can simply be run again.
"""

import argparse
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
MINIMUM_SYSTEM_VERSION = "14.0"


def sparkle_tag(name: str) -> str:
    return f"{{{SPARKLE}}}{name}"


def build_item(args: argparse.Namespace) -> ET.Element:
    item = ET.Element("item")
    ET.SubElement(item, "title").text = args.version
    ET.SubElement(item, "link").text = args.release_page
    ET.SubElement(item, sparkle_tag("version")).text = str(args.build)
    ET.SubElement(item, sparkle_tag("shortVersionString")).text = args.version
    ET.SubElement(item, sparkle_tag("minimumSystemVersion")).text = MINIMUM_SYSTEM_VERSION
    ET.SubElement(item, "pubDate").text = args.date
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": args.url,
            sparkle_tag("edSignature"): args.signature,
            "length": str(args.length),
            "type": "application/octet-stream",
        },
    )
    return item


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--appcast", default="appcast.xml")
    parser.add_argument("--version", required=True, help="CFBundleShortVersionString, e.g. 1.2.3")
    parser.add_argument("--build", required=True, type=int, help="CFBundleVersion of the built app")
    parser.add_argument("--url", required=True, help="download URL of the disk image")
    parser.add_argument("--length", required=True, type=int, help="size of the disk image in bytes")
    parser.add_argument("--signature", required=True, help="EdDSA signature from sign_update")
    parser.add_argument("--release-page", default=None)
    parser.add_argument("--date", default=None, help="RFC 822 pubDate, defaults to now")
    parser.add_argument("--stdout", action="store_true", help="print the feed instead of writing it")
    args = parser.parse_args()

    if args.release_page is None:
        args.release_page = f"https://github.com/my-monkeys/monkey-claude-usage/releases/tag/v{args.version}"
    if args.date is None:
        args.date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S %z")

    # Keeps the sparkle: prefix on output instead of ET's generated ns0:.
    ET.register_namespace("sparkle", SPARKLE)

    tree = ET.parse(args.appcast)
    channel = tree.getroot().find("channel")
    if channel is None:
        print(f"error: {args.appcast} has no <channel>", file=sys.stderr)
        return 1

    for existing in channel.findall("item"):
        if existing.findtext(sparkle_tag("shortVersionString")) == args.version:
            channel.remove(existing)

    items = channel.findall("item")
    position = list(channel).index(items[0]) if items else len(list(channel))
    channel.insert(position, build_item(args))

    ET.indent(tree, space="  ")
    output = ET.tostring(tree.getroot(), encoding="unicode", xml_declaration=True) + "\n"
    if args.stdout:
        sys.stdout.write(output)
    else:
        with open(args.appcast, "w", encoding="utf-8") as handle:
            handle.write(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
