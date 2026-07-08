cmake_minimum_required(VERSION 3.22.1)
project("linplayer_native")

# 注意：MPV 内核已迁移到 media_kit（Dart 封装库），
# 不再使用 FFI 直调 libmpv.so，因此不再需要 mpv_render_jni。
# libass 也通过 ExoPlayer 原生字幕管线和 media_kit 内置支持，
# 不再需要自定义 libass JNI。
# 此 CMakeLists.txt 保留最小配置，用于未来可能的扩展。

find_library(log-lib log)

# 如果未来需要添加原生模块，可以在此添加
# add_library(my_module SHARED my_module.cpp)
# target_link_libraries(my_module ${log-lib})
