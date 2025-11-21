# Camera Demo

Demo application demonstrating OpenCV camera capture using Allwinner VIN ISP interface on V851s platform.

## Structure

- `src/main.cpp` - Main application source
- `src/Makefile` - Source build configuration
- `Makefile` - Top-level build configuration

## Building

```bash
make
```

The build requires:
- OpenCV with VIN ISP support enabled
- Allwinner ISP libraries (libisp, libAWIspApi)
- C++ compiler with C++11 support

## Usage

Run the compiled binary to capture frames from the VIN camera interface. The demo showcases OpenCV VideoCapture integration with Allwinner's hardware ISP.

## Requirements

- Allwinner V851s platform
- OpenCV built with ENABLE_SUNXI_VIN_ISP=ON
- VIN camera device configured and accessible
