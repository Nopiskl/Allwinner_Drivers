# CedarX Libraries

Pre-built CedarX multimedia libraries and demo binaries for Allwinner A133 platform.

## Structure

### lib/
Multimedia codec and framework libraries including:
- Video codecs: H.264, H.265, VP8, MPEG4, WMV3
- Audio codecs: AAC, MP3, FLAC, Opus, AMR, Vorbis
- Media players and recorders (tplayer, trecorder, xplayer)
- RTSP/RTP streaming support (liveMedia, groupsock)
- Hardware video encoding/decoding interfaces

### bin/
Demo applications:
- `tplayerdemo` - Media player demonstration
- `trecorderdemo` - Media recorder demonstration  
- `jpegdecodedemo` - JPEG decoder demonstration

## Usage

### Library Path
Add the `lib/` directory to your library search path:
```bash
export LD_LIBRARY_PATH=/path/to/cedar_libs/lib:$LD_LIBRARY_PATH
```

### Running Demos
```bash
cd bin/
./tplayerdemo [media_file]
```

## Updating

Use the provided script to sync libraries from TinaSDK rootfs:
```bash
./update_cedar_libs.sh [ROOTFS_DIR]
```

Default ROOTFS_DIR: `../out/r818-sc3917/compile_dir/target/rootfs`

## Compatibility

- Target platform: Allwinner A133 (R818-SC3917)
- Architecture: ARM
- Build system: TinaSDK
