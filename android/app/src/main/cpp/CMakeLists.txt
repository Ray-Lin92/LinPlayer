cmake_minimum_required(VERSION 3.22.1)
project("linplayer_native")

find_library(log-lib log)

# ============================================================================
# libass JNI 桥接层
# 用于 ExoPlayer 内封/外挂 ASS 字幕的 libass 特效渲染
# 动态加载 libass.so (独立库) 或 libmpv.so (media_kit 内置)
# ============================================================================

add_library(linass_jni SHARED
    linass_jni.cpp
)

target_link_libraries(linass_jni
    ${log-lib}
    dl
)

# 确保 C++17 标准
target_compile_features(linass_jni PUBLIC cxx_std_17)

# 如果需要在未来添加其他原生模块，可以在此继续添加
# add_library(my_module SHARED my_module.cpp)
# target_link_libraries(my_module ${log-lib})
