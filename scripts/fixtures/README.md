# Public identity photo fixture

`public-identity.heic` is a genuine HEVC/HEIF image containing only this public secp256k1 key:

```text
0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
```

The QR was rendered with Core Image (`CIQRCodeGenerator`, correction M, integer scale 6 and a 24-pixel white border), then encoded with ImageIO as `public.heic` at quality 1. It contains no real wallet or account data.

The simulator runner stages a fresh copy in Photos before SDK-backed tests and advertises readiness through the loopback fixture. The Photos UI test selects it and compares the decoded key exactly. The copy's fresh date keeps it ahead of images from previous test runs; the later photo-export test creates and imports its own new QR with a fresh fixture wallet's identity.
