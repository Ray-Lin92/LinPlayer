Place pre-built libass.so here for arm64-v8a.

Build from source:
  git clone https://github.com/libass/libass
  cd libass && ./autogen.sh
  ./configure --host=aarch64-linux-android --enable-static --disable-shared
  make && cp .libs/libass.so ../jniLibs/arm64-v8a/

Or download pre-built from:
  https://github.com/nicehash/libass-android/releases
