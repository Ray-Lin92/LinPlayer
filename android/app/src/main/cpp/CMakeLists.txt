cmake_minimum_required(VERSION 3.22.1)
project("linass_jni")

set(ASS_INCLUDE_DIR ${CMAKE_SOURCE_DIR}/include)
set(ASS_LIB_DIR ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

set(LIBASS_FOUND FALSE)

if(EXISTS "${ASS_LIB_DIR}/libass.so")
    set(LIBASS_FOUND TRUE)
    message(STATUS "libass found: ${ASS_LIB_DIR}/libass.so")
else()
    message(WARNING "libass NOT found in ${ASS_LIB_DIR}, building stub")
endif()

add_library(linass_jni SHARED linass_jni.cpp)

target_include_directories(linass_jni PRIVATE
    ${ASS_INCLUDE_DIR}
)

if(LIBASS_FOUND)
    target_compile_definitions(linass_jni PRIVATE HAS_LIBASS)

    add_library(ass SHARED IMPORTED)
    set_target_properties(ass PROPERTIES
        IMPORTED_LOCATION "${ASS_LIB_DIR}/libass.so"
    )
endif()

find_library(log-lib log)

if(LIBASS_FOUND)
    target_link_libraries(linass_jni ass ${log-lib})
else()
    target_link_libraries(linass_jni ${log-lib})
endif()
