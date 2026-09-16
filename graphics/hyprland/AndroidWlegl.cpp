#include "../Compositor.hpp"
#include "../protocols/types/Buffer.hpp"
#include "../render/Renderer.hpp"
#include <hardware/gralloc.h>
#include <system/window.h>
#include <atomic>
#include <cstring>
#include <vector>
#include <unistd.h>
#include "wayland-android-protocol.h"

extern "C" {
int hybris_gralloc_allocate(int, int, int, int, buffer_handle_t*, uint32_t*);
int hybris_gralloc_import_buffer(buffer_handle_t, buffer_handle_t*);
int hybris_gralloc_release(buffer_handle_t, int);
}

namespace {
struct Native {
    ANativeWindowBuffer base{};
    std::atomic<unsigned> refs{1};
    bool allocated;
    static void retain(android_native_base_t* p) { ++reinterpret_cast<Native*>(p)->refs; }
    static void release(android_native_base_t* p) {
        auto n = reinterpret_cast<Native*>(p);
        if (--n->refs == 0) {
            hybris_gralloc_release(n->base.handle, n->allocated);
            delete n;
        }
    }
    Native(int w, int h, int stride, int format, int usage, buffer_handle_t handle, bool own) : allocated(own) {
        base.common.magic = ANDROID_NATIVE_BUFFER_MAGIC;
        base.common.version = sizeof(ANativeWindowBuffer);
        base.common.incRef = retain;
        base.common.decRef = release;
        base.width = w; base.height = h; base.stride = stride;
        base.format = format; base.usage = usage; base.handle = handle;
    }
};
class Buffer final : public IHLBuffer {
  public:
    Native* native;
    CHyprSignalListener destroyed;
    Buffer(Native* n) : native(n) {
        size = {n->base.width, n->base.height};
        m_opaque = opaque = n->base.format == HAL_PIXEL_FORMAT_RGBX_8888 || n->base.format == HAL_PIXEL_FORMAT_RGB_565;
    }
    ~Buffer() override {
        m_texture.reset();
        Native::release(&native->base.common);
    }
    Aquamarine::eBufferCapability caps() override { return Aquamarine::BUFFER_CAPABILITY_NONE; }
    Aquamarine::eBufferType type() override { return Aquamarine::BUFFER_TYPE_MISC; }
    void update(const CRegion&) override {}
    bool isSynchronous() override { return false; }
    bool good() override { return m_resource && m_resource->good(); }
    void* androidNativeBuffer() override { return &native->base; }
    // android_wlegl has no release-fence event: finish reads before permitting reuse.
    void sendRelease() override {
        if (!g_pCompositor || g_pCompositor->m_isShuttingDown || !g_pHyprRenderer)
            return;
        g_pHyprRenderer->makeEGLCurrent();
        glFinish();
        IHLBuffer::sendRelease();
    }
};
std::vector<SP<Buffer>> buffers;
struct Handle {
    int expected;
    std::vector<int> fds, ints;
    ~Handle() { for (int fd : fds) close(fd); }
};
void destroyHandle(wl_resource* r) { delete static_cast<Handle*>(wl_resource_get_user_data(r)); }
void destroyRequest(wl_client*, wl_resource* r) { wl_resource_destroy(r); }
void addFd(wl_client*, wl_resource* r, int fd) {
    auto h = static_cast<Handle*>(wl_resource_get_user_data(r));
    if (h->fds.size() >= static_cast<size_t>(h->expected)) {
        close(fd);
        wl_resource_post_error(r, ANDROID_WLEGL_HANDLE_ERROR_TOO_MANY_FDS, "too many fds");
        return;
    }
    h->fds.push_back(fd);
}
const struct android_wlegl_handle_interface handleImpl = {addFd, destroyRequest};
void createHandle(wl_client* c, wl_resource* r, uint32_t id, int32_t count, wl_array* ints) {
    if (count < 0 || count > 64 || ints->size % sizeof(int) || ints->size > 4096) {
        wl_resource_post_error(r, ANDROID_WLEGL_ERROR_BAD_VALUE, "invalid native handle size");
        return;
    }
    auto resource = wl_resource_create(c, &android_wlegl_handle_interface, 1, id);
    if (!resource) { wl_client_post_no_memory(c); return; }
    auto h = new Handle{count, {}, {}};
    h->ints.resize(ints->size / sizeof(int));
    if (ints->size) memcpy(h->ints.data(), ints->data, ints->size);
    wl_resource_set_implementation(resource, &handleImpl, h, destroyHandle);
}
SP<Buffer> wrap(wl_client* c, uint32_t id, Native* n) {
    auto b = makeShared<Buffer>(n);
    b->m_resource = CWLBufferResource::create(makeShared<CWlBuffer>(c, 1, id));
    if (!b->good()) { wl_client_post_no_memory(c); return nullptr; }
    b->m_resource->m_buffer = b;
    b->m_texture = makeShared<CTexture>(b);
    if (!b->m_texture->m_eglImage || !b->m_texture->m_texID) {
        wl_client_post_implementation_error(c, "vendor EGL rejected Android buffer");
        return nullptr;
    }
    b->destroyed = b->events.destroy.registerListener([ptr = b.get()](std::any) {
        ptr->destroyed.reset();
        std::erase_if(buffers, [ptr](const auto& b) { return b.get() == ptr; });
    });
    buffers.push_back(b);
    return b;
}
void createBuffer(wl_client* c, wl_resource* r, uint32_t id, int32_t w, int32_t h, int32_t stride, int32_t format, int32_t usage, wl_resource* hr) {
    if (w <= 0 || h <= 0 || w > 16384 || h > 16384 || stride < w ||
        !wl_resource_instance_of(hr, &android_wlegl_handle_interface, &handleImpl)) {
        wl_resource_post_error(r, ANDROID_WLEGL_ERROR_BAD_VALUE, "invalid buffer geometry or handle"); return;
    }
    auto handle = static_cast<Handle*>(wl_resource_get_user_data(hr));
    if (handle->fds.size() != static_cast<size_t>(handle->expected)) {
        wl_resource_post_error(r, ANDROID_WLEGL_ERROR_BAD_HANDLE, "fd count mismatch"); return;
    }
    auto raw = native_handle_create(handle->expected, handle->ints.size());
    if (!raw) { wl_client_post_no_memory(c); return; }
    memcpy(raw->data, handle->fds.data(), handle->fds.size() * sizeof(int));
    memcpy(raw->data + handle->expected, handle->ints.data(), handle->ints.size() * sizeof(int));
    buffer_handle_t imported = nullptr;
    int result = hybris_gralloc_import_buffer(raw, &imported);
    // The handle resource owns the received fds; mapper import duplicates them.
    native_handle_delete(raw);
    if (result || !imported) {
        wl_resource_post_error(r, ANDROID_WLEGL_ERROR_BAD_HANDLE, "gralloc import failed"); return;
    }
    wrap(c, id, new Native(w, h, stride, format, usage, imported, false));
}
void serverBuffer(wl_client* c, wl_resource* r, uint32_t id, int32_t w, int32_t h, int32_t format, int32_t usage) {
    if (w <= 0 || h <= 0 || w > 16384 || h > 16384) {
        wl_resource_post_error(r, ANDROID_WLEGL_ERROR_BAD_VALUE, "invalid buffer size"); return;
    }
    auto reply = wl_resource_create(c, &android_wlegl_server_buffer_handle_interface, 2, id);
    if (!reply) { wl_client_post_no_memory(c); return; }
    if (!format) format = HAL_PIXEL_FORMAT_RGBA_8888;
    usage |= GRALLOC_USAGE_HW_TEXTURE | GRALLOC_USAGE_HW_COMPOSER;
    buffer_handle_t handle = nullptr;
    uint32_t stride = 0;
    if (hybris_gralloc_allocate(w, h, format, usage, &handle, &stride) || !handle) {
        wl_resource_destroy(reply);
        wl_resource_post_error(r, ANDROID_WLEGL_ERROR_BAD_HANDLE, "gralloc allocation failed"); return;
    }
    auto b = wrap(c, 0, new Native(w, h, stride, format, usage, handle, true));
    if (b) {
        wl_array ints{static_cast<size_t>(handle->numInts) * sizeof(int), 0,
                      const_cast<int*>(handle->data + handle->numFds)};
        android_wlegl_server_buffer_handle_send_buffer_ints(reply, &ints);
        for (int i = 0; i < handle->numFds; ++i)
            android_wlegl_server_buffer_handle_send_buffer_fd(reply, handle->data[i]);
        android_wlegl_server_buffer_handle_send_buffer(reply, b->m_resource->getResource(), format, stride);
    }
    wl_resource_destroy(reply);
}
const struct android_wlegl_interface implementation = {createHandle, createBuffer, serverBuffer};
void bind(wl_client* c, void*, uint32_t version, uint32_t id) {
    auto r = wl_resource_create(c, &android_wlegl_interface, version, id);
    if (!r) { wl_client_post_no_memory(c); return; }
    wl_resource_set_implementation(r, &implementation, nullptr, nullptr);
}
}

bool initAndroidWlegl(wl_display* display) {
    return wl_global_create(display, &android_wlegl_interface, 2, nullptr, bind) != nullptr;
}
