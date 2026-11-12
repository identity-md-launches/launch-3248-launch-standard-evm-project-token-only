# Logo provenance

Website: https://midaswhale.wtf/xlongdog

Source post (X, source only): https://x.com/taylor_/status/2120975103148359750

Original photograph: https://pbs.twimg.com/media/HW83ZHFWEAAKK_C.jpg

`source-photo.jpg` is the downloaded, unmodified 1024×1024 photograph. `logo.png` is
an opaque, 8-bit RGB 512×512 PNG crop of that photograph. Coordinates are measured from
the top-left of the source: **x=176, y=224, width=512, height=512** (right and bottom
exclusive: 688, 736). No rescaling, drawing, retouching, text or frame was applied.
The face, eye, muzzle and ears sit within the inscribed circle of the square.

The existing FFmpeg tool performed only JPEG decoding, cropping and RGB PNG encoding:

```sh
ffmpeg -hide_banner -loglevel error -i assets/source-photo.jpg \
  -vf 'crop=512:512:176:224,format=rgb24' \
  -frames:v 1 -update 1 assets/logo.png
```

The delivered PNG is the authoritative artifact. Re-encoding with another decoder or
FFmpeg version may change encoded bytes; no image tool is needed to build or test Solidity.

| File | SHA-256 |
| --- | --- |
| `source-photo.jpg` | `258e74d370c20e5879bd3348418170b395c8e85f883143cf4e9daeed0d926418` |
| `logo.png` | `7d9f11b1a09415fe3f504d7f10a80502cba31c2ca67eb210c9400505baaf56a5` |

`python3 tools/metadata.py --write` embeds the delivered PNG in `metadata/token.json`.
`python3 tools/metadata.py` checks the existing package without changing files or reaching
the network. The source photograph is supplied for provenance, not as the final wallet logo.

The image is used as requested for this unofficial fan meme. No authorship, endorsement,
affiliation or software-license rights to the photograph are asserted. The MIT notices on
Solidity source do not relicense this photograph.
