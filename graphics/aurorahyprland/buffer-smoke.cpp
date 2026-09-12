#include "HybrisBuffer.hpp"

#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <stdexcept>

static void require(bool ok, const char* why) {
    if (!ok) throw std::runtime_error(why);
}

static int openFdCount() {
    DIR* dir = opendir("/proc/self/fd");
    require(dir != nullptr, "open fd inventory");
    int count = 0;
    while (const auto* entry = readdir(dir))
        if (entry->d_name[0] != '.') ++count;
    closedir(dir);
    return count;
}

int main() {
    // This gate must never acquire the phone's single-client composer HAL.
    setenv("EGL_PLATFORM", "null", 1);
    setenv("HYBRIS_EGLPLATFORM", "null", 1);
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface surface = EGL_NO_SURFACE;
    int result = 1;
    try {
        display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        require(display != EGL_NO_DISPLAY && eglInitialize(display, nullptr, nullptr), "EGL init");
        const EGLint attrs[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8,
            EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
        EGLConfig config = nullptr;
        EGLint count = 0;
        require(eglBindAPI(EGL_OPENGL_ES_API) &&
            eglChooseConfig(display, attrs, &config, 1, &count) && count == 1, "EGL config");
        const EGLint pb[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
        const EGLint ctx[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
        surface = eglCreatePbufferSurface(display, config, pb);
        context = eglCreateContext(display, config, EGL_NO_CONTEXT, ctx);
        require(surface != EGL_NO_SURFACE && context != EGL_NO_CONTEXT &&
            eglMakeCurrent(display, surface, surface, context), "EGL context");
        const char* vendor = eglQueryString(display, EGL_VENDOR);
        const char* renderer = reinterpret_cast<const char*>(glGetString(GL_RENDERER));
        require(vendor && renderer, "missing vendor identity");
        require(!strstr(vendor, "Mesa") && !strstr(renderer, "zink") &&
            !strstr(renderer, "llvmpipe") && !strstr(renderer, "Turnip"), "non-vendor renderer refused");
        std::printf("vendor=%s renderer=%s\n", vendor, renderer);
        auto bindImage = reinterpret_cast<PFNGLEGLIMAGETARGETRENDERBUFFERSTORAGEOESPROC>(
            eglGetProcAddress("glEGLImageTargetRenderbufferStorageOES"));
        require(bindImage, "native image renderbuffer entry point");
        bool invalidGeometryRejected = false;
        try {
            AuroraHyprland::HybrisBuffer invalid(display, 0, 64);
        } catch (const std::runtime_error&) {
            invalidGeometryRejected = true;
        }
        require(invalidGeometryRejected, "invalid geometry was accepted");
        int steadyFds = -1;
        for (int round = 0; round < 10; ++round) {
          {
            AuroraHyprland::HybrisBuffer buffer(display, 64, 64);
            bool invalidFenceRejected = false;
            try {
                buffer.waitReleaseFence(-2);
            } catch (const std::runtime_error&) {
                invalidFenceRejected = true;
            }
            require(invalidFenceRejected, "invalid fence was accepted");
            int ints = 0, fds = 0;
            buffer.handleCounts(ints, fds);
            require(fds > 0 && ints >= 0, "complete Android native handle");
            std::printf("native_handle fds=%d ints=%d stride=%d\n", fds, ints, buffer.stride());
            GLuint fbo = 0, rbo = 0;
            glGenFramebuffers(1, &fbo);
            glGenRenderbuffers(1, &rbo);
            glBindRenderbuffer(GL_RENDERBUFFER, rbo);
            bindImage(GL_RENDERBUFFER, buffer.image());
            glBindFramebuffer(GL_FRAMEBUFFER, fbo);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rbo);
            require(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "native FBO");
            glViewport(0, 0, 64, 64);
            for (int frame = 0; frame < 120; ++frame) {
                const unsigned char red = frame % 2 ? 255 : 0;
                glClearColor(red / 255.0f, 1.0f, 0.0f, 1.0f);
                glClear(GL_COLOR_BUFFER_BIT);
                require(glGetError() == GL_NO_ERROR, "vendor GLES render");
                buffer.waitReleaseFence(buffer.exportRenderFence());
                auto* pixels = static_cast<unsigned char*>(buffer.lockForRead());
                bool matches = pixels != nullptr;
                if (pixels) {
                    for (int y = 0; y < 64; ++y)
                        for (int x = 0; x < 64; ++x) {
                            const auto* p = pixels + (y * buffer.stride() + x) * 4;
                            matches = matches && p[0] == red && p[1] == 255 && p[2] == 0 && p[3] == 255;
                        }
                }
                buffer.unlock();
                require(matches, "gralloc readback mismatch");
            }
            glDeleteFramebuffers(1, &fbo);
            glDeleteRenderbuffers(1, &rbo);
          }
          const int fds = openFdCount();
          std::printf("round=%d open_fds=%d\n", round + 1, fds);
          // Ignore lazy driver initialization before enforcing steady-state ownership.
          if (round == 1) steadyFds = fds;
          if (round > 1) require(fds == steadyFds, "fd count changed after warmup");
        }
        std::puts("PASS: AuroraHyprland native-buffer foundation, 1200 vendor-render/fence/readback cycles, stable fds, invalid geometry/fence rejected");
        std::puts("NOT QUALIFIED: Aquamarine output, Hyprland renderer integration, HWC and input remain");
        result = 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "FAIL: %s (EGL %#x)\n", error.what(), eglGetError());
    }
    if (display != EGL_NO_DISPLAY) {
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (context != EGL_NO_CONTEXT) eglDestroyContext(display, context);
        if (surface != EGL_NO_SURFACE) eglDestroySurface(display, surface);
        eglTerminate(display);
    }
    return result;
}
