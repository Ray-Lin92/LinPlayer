#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <android/log.h>

#define LOG_TAG "LinassJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#ifdef HAS_LIBASS
#include <ass/ass.h>

typedef struct {
    ass_library_t *library;
    ass_renderer_t *renderer;
    ass_track_t *track;
} LinassContext;

static LinassContext g_ctx = {NULL, NULL, NULL};
#endif

JNIEXPORT jboolean JNICALL
Java_com_example_linplayer_1mobile_LibassBridge_nativeIsAvailable(JNIEnv *env, jobject thiz) {
#ifdef HAS_LIBASS
    return ass_library_init() != NULL ? JNI_TRUE : JNI_FALSE;
#else
    return JNI_FALSE;
#endif
}

JNIEXPORT jlong JNICALL
Java_com_example_linplayer_1mobile_LibassBridge_nativeInit(JNIEnv *env, jobject thiz, jint width, jint height) {
#ifdef HAS_LIBASS
    if (g_ctx.library) {
        ass_library_done(g_ctx.library);
    }
    if (g_ctx.renderer) {
        ass_renderer_done(g_ctx.renderer);
    }

    g_ctx.library = ass_library_init();
    if (!g_ctx.library) {
        LOGE("Failed to init ass_library");
        return 0;
    }

    ass_set_extract_fonts(g_ctx.library, 1);
    ass_set_style_overrides(g_ctx.library, NULL);

    g_ctx.renderer = ass_renderer_init(g_ctx.library);
    if (!g_ctx.renderer) {
        LOGE("Failed to init ass_renderer");
        ass_library_done(g_ctx.library);
        g_ctx.library = NULL;
        return 0;
    }

    ass_set_frame_size(g_ctx.renderer, width, height);
    ass_set_storage_size(g_ctx.renderer, width, height);
    ass_set_use_margins(g_ctx.renderer, 0);
    ass_set_font_scale(g_ctx.renderer, 1.0);
    ass_set_hinting(g_ctx.renderer, ASS_HINTING_LIGHT);
    ass_set_line_spacing(g_ctx.renderer, 0.0);

    LOGI("libass init: %dx%d", width, height);
    return (jlong)(intptr_t)g_ctx.library;
#else
    LOGE("libass not available");
    return 0;
#endif
}

JNIEXPORT jlong JNICALL
Java_com_example_linplayer_1mobile_LibassBridge_nativeLoadFile(JNIEnv *env, jobject thiz, jlong handle, jstring path) {
#ifdef HAS_LIBASS
    if (!g_ctx.library) return 0;
    const char *cpath = (*env)->GetStringUTFChars(env, path, NULL);
    g_ctx.track = ass_read_file(g_ctx.library, (char *)cpath, NULL);
    (*env)->ReleaseStringUTFChars(env, path, cpath);
    if (!g_ctx.track) {
        LOGE("Failed to load sub file");
        return 0;
    }
    LOGI("Loaded sub file, %d events", g_ctx.track->n_events);
    return (jlong)(intptr_t)g_ctx.track;
#else
    return 0;
#endif
}

JNIEXPORT jlong JNICALL
Java_com_example_linplayer_1mobile_LibassBridge_nativeLoadMemory(JNIEnv *env, jobject thiz, jlong handle, jbyteArray data, jstring codec) {
#ifdef HAS_LIBASS
    if (!g_ctx.library) return 0;
    jsize len = (*env)->GetArrayLength(env, data);
    jbyte *buf = (*env)->GetByteArrayElements(env, data, NULL);
    const char *ccodec = (*env)->GetStringUTFChars(env, codec, NULL);

    g_ctx.track = ass_read_memory(g_ctx.library, (char *)buf, (size_t)len, (char *)ccodec);

    (*env)->ReleaseByteArrayElements(env, data, buf, JNI_ABORT);
    (*env)->ReleaseStringUTFChars(env, codec, ccodec);

    if (!g_ctx.track) {
        LOGE("Failed to load sub from memory");
        return 0;
    }
    LOGI("Loaded sub memory, %d events", g_ctx.track->n_events);
    return (jlong)(intptr_t)g_ctx.track;
#else
    return 0;
#endif
}

JNIEXPORT void JNICALL
Java_com_example_linplayer_1mobile_LibassBridge_nativeSetFontSize(JNIEnv *env, jobject thiz, jlong handle, jint size) {
#ifdef HAS_LIBASS
    if (!g_ctx.renderer) return;
    ass_set_font_scale(g_ctx.renderer, (double)size / 48.0);
#endif
}

JNIEXPORT void JNICALL
Java_com_example_linplayer_1mobile_LibassBridge_nativeSetFontName(JNIEnv *env, jobject thiz, jlong handle, jstring name) {
#ifdef HAS_LIBASS
    if (!g_ctx.renderer) return;
    const char *cname = (*env)->GetStringUTFChars(env, name, NULL);
    ass_set_default_font(g_ctx.renderer, (char *)cname, NULL);
    (*env)->ReleaseStringUTFChars(env, name, cname);
#endif
}

JNIEXPORT jbyteArray JNICALL
Java_com_example_linplayer_1mobile_LibassBridge_nativeRenderFrame(JNIEnv *env, jobject thiz, jlong rhandle, jlong thandle, jlong ptsMs) {
#ifdef HAS_LIBASS
    if (!g_ctx.renderer || !g_ctx.track) return NULL;

    int changed = 0;
    ass_image_t *img = ass_render_frame(g_ctx.renderer, g_ctx.track, ptsMs * 1000, &changed);

    if (!img) return NULL;

    int totalSize = 0;
    ass_image_t *cur = img;
    while (cur) {
        totalSize += cur->w * cur->h * 4 + 12;
        cur = cur->next;
    }
    if (totalSize == 0) return NULL;

    jbyteArray result = (*env)->NewByteArray(env, totalSize);
    jbyte *out = (*env)->GetByteArrayElements(env, result, NULL);
    int offset = 0;

    cur = img;
    while (cur) {
        int w = cur->w;
        int h = cur->h;
        int stride = cur->stride;
        unsigned int color = cur->color;
        unsigned char r = (color >> 24) & 0xFF;
        unsigned char g = (color >> 16) & 0xFF;
        unsigned char b = (color >> 8) & 0xFF;
        unsigned char a = (color) & 0xFF;

        ((int *)out)[offset / 4] = w; offset += 4;
        ((int *)out)[offset / 4] = h; offset += 4;
        ((int *)out)[offset / 4] = stride; offset += 4;

        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                unsigned char alpha = cur->bitmap[y * stride + x];
                out[offset++] = r;
                out[offset++] = g;
                out[offset++] = b;
                out[offset++] = (unsigned char)((alpha * (255 - a)) / 255);
            }
        }
        cur = cur->next;
    }

    (*env)->ReleaseByteArrayElements(env, result, out, 0);
    return result;
#else
    return NULL;
#endif
}

JNIEXPORT void JNICALL
Java_com_example_linplayer_1mobile_LibassBridge_nativeDispose(JNIEnv *env, jobject thiz, jlong lhandle, jlong rhandle, jlong thandle) {
#ifdef HAS_LIBASS
    if (g_ctx.track) {
        ass_free_track(g_ctx.track);
        g_ctx.track = NULL;
    }
    if (g_ctx.renderer) {
        ass_renderer_done(g_ctx.renderer);
        g_ctx.renderer = NULL;
    }
    if (g_ctx.library) {
        ass_library_done(g_ctx.library);
        g_ctx.library = NULL;
    }
    LOGI("libass disposed");
#endif
}
