# OpenCV Build Configuration

Build configuration and patches for OpenCV with Allwinner VIN ISP support.

## Contents

- `Config.in` - Build configuration options
- `Makefile` - Build instructions for integrating with TinaSDK/Buildroot
- `patches/` - Patch files for OpenCV source

## Patches

### 900-support-sunxi-vin-camera.patch
Adds Sunxi VIN camera backend to OpenCV VideoIO module:
- Introduces `WITH_VIN_ISP` and `ENABLE_SUNXI_VIN_ISP` CMake options
- Integrates VIN ISP libraries (libisp, libAWIspApi) into OpenCV build
- Enables hardware ISP through OpenCV VideoCapture API
- Adds VIN ISP detection and status reporting

## Building

This directory is designed to work with Buildroot/TinaSDK build systems. The Makefile handles:
- OpenCV source download and extraction
- Patch application
- Cross-compilation configuration
- Installation to target rootfs

### Manual Build
To manually apply patches to OpenCV source:
```bash
cd /path/to/opencv-source
patch -p1 < patches/900-support-sunxi-vin-camera.patch
```

Then configure with:
```bash
cmake -DENABLE_SUNXI_VIN_ISP=ON -DWITH_VIN_ISP=ON ...
```

## Requirements

- OpenCV 3.x or 4.x source
- Allwinner VIN ISP SDK (libisp, libAWIspApi, isp_ini)
- CMake 3.x
- C++ compiler with C++11 support

## Integration

The patch integrates seamlessly with OpenCV's VideoCapture interface, allowing standard OpenCV code to utilize hardware-accelerated ISP on Allwinner platforms.
