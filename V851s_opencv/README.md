# OpenCV with VIN ISP for Allwinner V851s

OpenCV integration with Allwinner VIN ISP support for V851s platform, enabling hardware-accelerated image processing and camera capture.

## Contents

### opencv/
OpenCV build configuration and patches for Allwinner VIN ISP integration:
- `patches/900-support-sunxi-vin-camera.patch` - Adds Sunxi VIN camera backend support to OpenCV

### camerademo_self/
Demo application showing OpenCV camera capture using VIN ISP interface.

### New patch/
Additional kernel patches:
- `901-VIN-ENABLE-HARD.patch` - Hardware VIN enablement patch

## Building

### OpenCV with VIN ISP
Build OpenCV with the provided patches and enable VIN ISP support:
```bash
cd opencv/
# Apply patches during OpenCV build
# Enable ENABLE_SUNXI_VIN_ISP=ON in CMake configuration
```

### Camera Demo
```bash
cd camerademo_self/
make
```

## Requirements

- Allwinner V851s platform
- VIN ISP libraries (libisp, libAWIspApi)
- OpenCV dependencies

## Features

- Hardware-accelerated ISP processing
- Native V4L2-like camera interface for Allwinner VIN
- Compatible with standard OpenCV VideoCapture API
