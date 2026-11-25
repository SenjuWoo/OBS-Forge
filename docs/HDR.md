# HDR, SDR and the two errors this pack prevents

## The short version

The stream is **SDR**. The profiles are 8-bit Rec.709 so the stream encoder can start and
every player shows the right colours. Windows HDR can stay on; OBS converts an HDR source
to the SDR canvas for you.

## The two errors

Both come from an HDR canvas under an 8-bit H.264 stream encoder:

```
[obs-nvenc] NVENC Error: OBS does not support 8-bit output of Rec. 2100.
[obs-nvenc] NVENC Error: Cannot perform 10-bit encode on this encoder.
Stream output type 'rtmp_output' failed to start!  Last Error: NVENC Error: ...
```

| You set | What happens |
|---|---|
| Colour space **Rec. 2100 (PQ/HLG)**, format **NV12** | 8-bit canvas asked to output Rec.2100 → first error |
| Format **P010** (10-bit), stream encoder **H.264** | H.264 is 8-bit only → second error, stream never starts |

The fix is not a driver setting: it is keeping the canvas at **NV12 / Rec.709 / Partial**
and letting OBS tone-map. `Verify.ps1` fails if a profile drifts.

## Which destinations take HDR

| Destination | HDR live | Codec / format |
|---|---|---|
| Twitch | No | H.264 8-bit up to 1080p; HEVC only for 1440p Enhanced Broadcasting |
| Kick | No | H.264 8-bit |
| Rumble | No | H.264 8-bit |
| YouTube | Yes | HEVC **Main10**, P010, Rec.2100 PQ or HLG, 9–12 Mbps |

YouTube is the only one, and it needs a **second** encode. A restreaming tool that
forwards OBS's single output cannot re-encode it, so YouTube HDR means a second OBS
instance or a second encoder running while you play — for a source that is usually SDR
anyway (console remote play, most PC games in SDR).

## If you really want HDR on YouTube

1. Keep this pack's SDR profile for Twitch/Kick/Rumble.
2. Run a second OBS instance (or a second output) with: format **P010**, colour space
   **Rec. 2100 (PQ)**, HEVC **Main10**, 9–12 Mbps, 2 s keyframes.
3. Point that instance at YouTube only.
4. Accept the extra GPU load, or lower the game's settings.

There is no switch in this pack that does it, on purpose.

## Windows HDR and tone mapping

Windows HDR on + an HDR game + this SDR canvas = OBS tone-maps. The knob is
**Settings → Advanced → Video → SDR White Level** (300 here):

- HDR game looks **darker** than your screen → lower toward 200.
- Looks **washed out or clipped** → raise toward 400.

An SDR source (console remote play, most desktop capture) is untouched by this setting.

## Quick check

```powershell
.\Verify.ps1
```

It prints the colour format/space/range of both profiles, the encoder profiles, and scans
the newest OBS log for the two errors above.