QR Code Encoder
===============

Reference used was ISO/IEC 18004, 1st Edition (2000)

This library is derived from Steve Davis' original implementation which was
designed to enable Google 2FA on mobile phones.

The current requirements for this library are driven by the need to encode
URLs for mobile devices and browsers, in particular to enable QR code PNG
generation in the backend of pay.aegora.jp.

The QR generation code itself has not been changed much at all, just reorganized
a little bit to streamline calls.

QR detection, kanji mode, decoding, etc. are not supported.
