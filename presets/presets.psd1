# OBS-Forge preset catalogue.
#
# One entry = one OBS profile. Install.ps1 builds basic.ini and the encoder JSON for the
# encoder family it detects (NVENC, AMF, Quick Sync or x264), so every preset works on every
# GPU. Add a preset by copying an entry; Verify.ps1 and Uninstall.ps1 pick it up.
#
#   Id           what you type after -Preset
#   Name         the profile name shown in OBS (must start with 'OBS-Forge ')
#   Group        menu heading
#   For          one line for the menu
#   Width/Height canvas = output resolution
#   Fps          frames per second
#   StreamCodec  h264 or hevc (x264 has no HEVC and falls back to H.264 at H264Kbps)
#   StreamKbps   video bitrate for StreamCodec
#   H264Kbps     video bitrate when the stream falls back to H.264 (hevc presets only)
#   Record       light   = cheap second encoder that runs while you play and stream
#                quality = high-quality recording for record-only use
#   StreamRescale optional WxH the stream is scaled to (recording keeps the full canvas)
#   Collection   scene collection the preset is meant for
#   Recommended  installed when no -Preset is given
#
# Bitrates: Twitch broadcasting guidelines (6000 / 4500 / 4500 / 3000 kbps, 2 s keyframes,
# AAC max 160 kbps) and YouTube's live encoder table (HEVC 12 / 24 Mbps, H.264 17 / 34 Mbps
# at 1080p60 / 1440p60). Kick caps at 8000 kbps H.264, so the Stream presets fit it too.

@{
    Presets = @(
        @{
            Id = '1080p60'; Name = 'OBS-Forge 1080p60'; Group = 'Stream'
            For = 'Twitch / Kick / Rumble, 1080p 60 fps, needs ~7 Mbps upload'
            Width = 1920; Height = 1080; Fps = 60
            StreamCodec = 'h264'; StreamKbps = 6000; Record = 'light'
            Collection = 'OBS-Forge'; Recommended = $true
        }
        @{
            Id = '1080p30'; Name = 'OBS-Forge 1080p30'; Group = 'Stream'
            For = 'Twitch / Kick / Rumble, 1080p 30 fps, needs ~5.5 Mbps upload'
            Width = 1920; Height = 1080; Fps = 30
            StreamCodec = 'h264'; StreamKbps = 4500; Record = 'light'
            Collection = 'OBS-Forge'; Recommended = $true
        }
        @{
            Id = '720p60'; Name = 'OBS-Forge 720p60'; Group = 'Stream'
            For = 'Smooth motion on a slower line or older GPU, needs ~5.5 Mbps upload'
            Width = 1280; Height = 720; Fps = 60
            StreamCodec = 'h264'; StreamKbps = 4500; Record = 'light'
            Collection = 'OBS-Forge'
        }
        @{
            Id = '720p30'; Name = 'OBS-Forge 720p30'; Group = 'Stream'
            For = 'Weak PC or slow upload, needs ~4 Mbps upload'
            Width = 1280; Height = 720; Fps = 30
            StreamCodec = 'h264'; StreamKbps = 3000; Record = 'light'
            Collection = 'OBS-Forge'
        }
        @{
            Id = 'youtube-1080p60'; Name = 'OBS-Forge YouTube 1080p60'; Group = 'YouTube'
            For = 'YouTube Live, HEVC 12 Mbps (H.264 17 Mbps on CPU encoding)'
            Width = 1920; Height = 1080; Fps = 60
            StreamCodec = 'hevc'; StreamKbps = 12000; H264Kbps = 17000; Record = 'light'
            Collection = 'OBS-Forge'
        }
        @{
            Id = 'youtube-1440p60'; Name = 'OBS-Forge YouTube 1440p60'; Group = 'YouTube'
            For = 'YouTube Live at 1440p, HEVC 24 Mbps, needs ~28 Mbps upload'
            Width = 2560; Height = 1440; Fps = 60
            StreamCodec = 'hevc'; StreamKbps = 24000; H264Kbps = 34000; Record = 'light'
            Collection = 'OBS-Forge'
        }
        @{
            Id = 'record-1080p60'; Name = 'OBS-Forge Record 1080p60'; Group = 'Record'
            For = 'Recording only: high-quality 1080p60 files for editing'
            Width = 1920; Height = 1080; Fps = 60
            StreamCodec = 'h264'; StreamKbps = 6000; Record = 'quality'
            Collection = 'OBS-Forge'
        }
        @{
            Id = 'record-1440p60'; Name = 'OBS-Forge Record 1440p60'; Group = 'Record'
            For = 'Recording only at 1440p60; streaming from it is scaled to 1080p'
            Width = 2560; Height = 1440; Fps = 60
            StreamCodec = 'h264'; StreamKbps = 6000; Record = 'quality'; StreamRescale = '1920x1080'
            Collection = 'OBS-Forge'
        }
        @{
            Id = 'vertical'; Name = 'OBS-Forge Vertical 1080x1920'; Group = 'Vertical'
            For = 'TikTok / Shorts / vertical live, 9:16 at 30 fps, 6000 kbps'
            Width = 1080; Height = 1920; Fps = 30
            StreamCodec = 'h264'; StreamKbps = 6000; Record = 'light'
            Collection = 'OBS-Forge Vertical'
        }
    )
}
