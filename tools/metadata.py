#!/usr/bin/env python3
"""Build/check the self-contained branding package using only Python's standard library."""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
WEBSITE = "https://midaswhale.wtf/xlongdog"
SOURCE_POST = "https://x.com/taylor_/status/2120975103148359750"
SOURCE_IMAGE = "https://pbs.twimg.com/media/HW83ZHFWEAAKK_C.jpg"
DESCRIPTION = (
    "Extremely Long Dog ($XLONGDOG): the longest dog on Robinhood Chain. "
    "A community meme token for the extremely long dog from @taylor_'s viral post. "
    "Unofficial fan meme, not affiliated with or endorsed by the post's author. "
    "Website: https://midaswhale.wtf/xlongdog | "
    "Source post: https://x.com/taylor_/status/2120975103148359750"
)
LOGO_SHA256 = "7d9f11b1a09415fe3f504d7f10a80502cba31c2ca67eb210c9400505baaf56a5"
PHOTO_SHA256 = "258e74d370c20e5879bd3348418170b395c8e85f883143cf4e9daeed0d926418"


def check_png(data):
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "image must be PNG"
    pos = 8
    kinds = []
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        crc = struct.unpack(">I", data[pos + 8 + length:pos + 12 + length])[0]
        assert zlib.crc32(kind + body) == crc, "invalid PNG chunk checksum"
        if kind == b"IHDR":
            width, height, depth, color, _, _, _ = struct.unpack(">IIBBBBB", body)
            assert width == height and width >= 512, "logo must be square and at least 512px"
            assert depth == 8 and color == 2, "logo must be opaque RGB"
        assert kind != b"tRNS", "logo must not contain transparency"
        kinds.append(kind)
        pos += 12 + length
    assert pos == len(data) and kinds[0] == b"IHDR" and kinds[-1] == b"IEND"
    assert b"IDAT" in kinds


def expected_metadata(logo):
    return {
        "name": "Extremely Long Dog",
        "symbol": "XLONGDOG",
        "decimals": 18,
        "description": DESCRIPTION,
        "image": "data:image/png;base64," + base64.b64encode(logo).decode("ascii"),
        "external_url": WEBSITE,
        "website": WEBSITE,
        "links": {"website": WEBSITE, "x": SOURCE_POST},
        "socials": {"x": SOURCE_POST},
        "source_post": SOURCE_POST,
        "source_image": SOURCE_IMAGE,
        "social_link_note": "Source post only; not an official account of @taylor_.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="regenerate metadata/token.json from the delivered PNG")
    args = parser.parse_args()
    logo = (ROOT / "assets/logo.png").read_bytes()
    photo = (ROOT / "assets/source-photo.jpg").read_bytes()
    check_png(logo)
    assert hashlib.sha256(logo).hexdigest() == LOGO_SHA256, "unexpected logo bytes"
    assert hashlib.sha256(photo).hexdigest() == PHOTO_SHA256, "unexpected source photo bytes"
    expected = expected_metadata(logo)
    path = ROOT / "metadata/token.json"
    if args.write:
        path.write_text(json.dumps(expected, indent=2) + "\n", encoding="utf-8")
    actual = json.loads(path.read_text(encoding="utf-8"))
    assert actual == expected, "metadata does not match the approved branding and logo"
    encoded_image = actual["image"].removeprefix("data:image/png;base64,")
    assert base64.b64decode(encoded_image, validate=True) == logo
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert DESCRIPTION in readme, "README must contain the exact official bio"
    assert WEBSITE in readme and SOURCE_POST in readme
    print("Metadata OK: exact bio and links, original photo provenance, opaque 512px PNG, embedded image matches.")


if __name__ == "__main__":
    main()
