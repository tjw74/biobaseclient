#include "include/cs2_capture/cs2_capture_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <d3d11.h>
#include <dxgi.h>
#include <inspectable.h>
#include <windows.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>

namespace {

using winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool;
using winrt::Windows::Graphics::Capture::GraphicsCaptureItem;
using winrt::Windows::Graphics::Capture::GraphicsCaptureSession;
using winrt::Windows::Graphics::DirectX::DirectXPixelFormat;
using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;

// Finds the game window: exact title match wins ("Counter-Strike 2"), a
// contains-match is kept as fallback (skipping browsers whose tab titles can
// contain the search string).
struct FindWindowContext {
  std::wstring needle;
  HWND exact = nullptr;
  HWND partial = nullptr;
};

BOOL CALLBACK EnumWindowsProc(HWND hwnd, LPARAM lparam) {
  auto* ctx = reinterpret_cast<FindWindowContext*>(lparam);
  if (!IsWindowVisible(hwnd)) return TRUE;
  wchar_t title[512];
  const int len = GetWindowTextW(hwnd, title, 512);
  if (len <= 0) return TRUE;
  std::wstring text(title, static_cast<size_t>(len));
  if (text == L"Counter-Strike 2") {
    ctx->exact = hwnd;
    return FALSE;
  }
  if (ctx->partial == nullptr &&
      text.find(ctx->needle) != std::wstring::npos) {
    wchar_t cls[256];
    const int cls_len = GetClassNameW(hwnd, cls, 256);
    std::wstring cls_text(cls, static_cast<size_t>(cls_len > 0 ? cls_len : 0));
    // Browsers render tab titles into their window title; never capture them.
    if (cls_text.find(L"Chrome_WidgetWin") == std::wstring::npos &&
        cls_text.find(L"MozillaWindowClass") == std::wstring::npos) {
      ctx->partial = hwnd;
    }
  }
  return TRUE;
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int size =
      MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                          static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring wide(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), size);
  return wide;
}

class Cs2CapturePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit Cs2CapturePlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar) {}

  ~Cs2CapturePlugin() override { StopCapture(); }

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool StartCapture(const std::string& title_contains, std::string* error);
  void StopCapture();
  void OnFrameArrived(const Direct3D11CaptureFramePool& pool);
  bool EnsureSharedTexture(uint32_t width, uint32_t height);

  flutter::PluginRegistrarWindows* registrar_ = nullptr;

  // D3D
  winrt::com_ptr<ID3D11Device> d3d_device_;
  winrt::com_ptr<ID3D11DeviceContext> d3d_context_;
  IDirect3DDevice winrt_device_{nullptr};

  // WGC
  GraphicsCaptureItem item_{nullptr};
  Direct3D11CaptureFramePool frame_pool_{nullptr};
  GraphicsCaptureSession session_{nullptr};
  winrt::event_token frame_arrived_token_{};

  // Shared texture handed to Flutter
  std::mutex texture_mutex_;
  winrt::com_ptr<ID3D11Texture2D> shared_texture_;
  HANDLE shared_handle_ = nullptr;
  uint32_t texture_width_ = 0;
  uint32_t texture_height_ = 0;

  std::unique_ptr<flutter::TextureVariant> texture_variant_;
  std::unique_ptr<FlutterDesktopGpuSurfaceDescriptor> surface_descriptor_;
  int64_t texture_id_ = -1;
  std::atomic<bool> capturing_{false};
};

// static
void Cs2CapturePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "biobase/cs2_capture",
          &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<Cs2CapturePlugin>(registrar);
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

void Cs2CapturePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "start") {
    std::string title = "Counter-Strike";
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = args->find(flutter::EncodableValue("title"));
      if (it != args->end()) {
        if (const auto* value = std::get_if<std::string>(&it->second)) {
          title = *value;
        }
      }
    }
    std::string error;
    if (!StartCapture(title, &error)) {
      result->Error("capture_failed", error);
      return;
    }
    flutter::EncodableMap response;
    response[flutter::EncodableValue("textureId")] =
        flutter::EncodableValue(texture_id_);
    response[flutter::EncodableValue("width")] =
        flutter::EncodableValue(static_cast<int32_t>(texture_width_));
    response[flutter::EncodableValue("height")] =
        flutter::EncodableValue(static_cast<int32_t>(texture_height_));
    result->Success(flutter::EncodableValue(response));
    return;
  }
  if (call.method_name() == "stop") {
    StopCapture();
    result->Success();
    return;
  }
  result->NotImplemented();
}

bool Cs2CapturePlugin::StartCapture(const std::string& title_contains,
                                    std::string* error) {
  if (capturing_) StopCapture();

  FindWindowContext ctx;
  ctx.needle = Utf8ToWide(title_contains);
  EnumWindows(EnumWindowsProc, reinterpret_cast<LPARAM>(&ctx));
  HWND target = ctx.exact ? ctx.exact : ctx.partial;
  if (!target) {
    *error = "window not found";
    return false;
  }
  // Never capture our own window.
  if (registrar_->GetView() &&
      target == GetAncestor(registrar_->GetView()->GetNativeWindow(),
                            GA_ROOT)) {
    *error = "matched own window";
    return false;
  }

  try {
    if (!d3d_device_) {
      UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
      HRESULT hr = D3D11CreateDevice(
          nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, nullptr, 0,
          D3D11_SDK_VERSION, d3d_device_.put(), nullptr, d3d_context_.put());
      if (FAILED(hr)) {
        *error = "D3D11CreateDevice failed";
        return false;
      }
      winrt::com_ptr<IDXGIDevice> dxgi_device = d3d_device_.as<IDXGIDevice>();
      winrt::com_ptr<::IInspectable> inspectable;
      hr = CreateDirect3D11DeviceFromDXGIDevice(dxgi_device.get(),
                                                inspectable.put());
      if (FAILED(hr)) {
        *error = "CreateDirect3D11DeviceFromDXGIDevice failed";
        return false;
      }
      winrt_device_ = inspectable.as<IDirect3DDevice>();
    }

    auto interop_factory =
        winrt::get_activation_factory<GraphicsCaptureItem,
                                      IGraphicsCaptureItemInterop>();
    GraphicsCaptureItem item{nullptr};
    HRESULT hr = interop_factory->CreateForWindow(
        target, winrt::guid_of<GraphicsCaptureItem>(),
        winrt::put_abi(item));
    if (FAILED(hr) || !item) {
      *error = "CreateForWindow failed";
      return false;
    }
    item_ = item;

    const auto size = item_.Size();
    const auto width = static_cast<uint32_t>(size.Width);
    const auto height = static_cast<uint32_t>(size.Height);
    if (!EnsureSharedTexture(width, height)) {
      *error = "shared texture creation failed";
      return false;
    }

    // Register the Flutter GPU surface texture once.
    if (texture_id_ < 0) {
      texture_variant_ = std::make_unique<flutter::TextureVariant>(
          flutter::GpuSurfaceTexture(
              kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
              [this](size_t, size_t) -> const FlutterDesktopGpuSurfaceDescriptor* {
                std::lock_guard<std::mutex> lock(texture_mutex_);
                if (!shared_handle_) return nullptr;
                surface_descriptor_ =
                    std::make_unique<FlutterDesktopGpuSurfaceDescriptor>();
                surface_descriptor_->struct_size =
                    sizeof(FlutterDesktopGpuSurfaceDescriptor);
                surface_descriptor_->handle = shared_handle_;
                surface_descriptor_->width = texture_width_;
                surface_descriptor_->height = texture_height_;
                surface_descriptor_->visible_width = texture_width_;
                surface_descriptor_->visible_height = texture_height_;
                surface_descriptor_->format =
                    kFlutterDesktopPixelFormatBGRA8888;
                surface_descriptor_->release_context = nullptr;
                surface_descriptor_->release_callback = [](void*) {};
                return surface_descriptor_.get();
              }));
      texture_id_ = registrar_->texture_registrar()->RegisterTexture(
          texture_variant_.get());
    }

    frame_pool_ = Direct3D11CaptureFramePool::CreateFreeThreaded(
        winrt_device_, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
    frame_arrived_token_ = frame_pool_.FrameArrived(
        [this](const Direct3D11CaptureFramePool& pool, const auto&) {
          OnFrameArrived(pool);
        });
    session_ = frame_pool_.CreateCaptureSession(item_);
    session_.IsCursorCaptureEnabled(false);
    try {
      session_.IsBorderRequired(false);
    } catch (...) {
      // Requires Windows 11 / consent on some builds; cosmetic only.
    }
    session_.StartCapture();
    capturing_ = true;
    return true;
  } catch (const winrt::hresult_error& e) {
    *error = winrt::to_string(e.message());
    return false;
  } catch (...) {
    *error = "unknown WGC failure";
    return false;
  }
}

bool Cs2CapturePlugin::EnsureSharedTexture(uint32_t width, uint32_t height) {
  std::lock_guard<std::mutex> lock(texture_mutex_);
  if (shared_texture_ && width == texture_width_ &&
      height == texture_height_) {
    return true;
  }
  shared_texture_ = nullptr;
  shared_handle_ = nullptr;

  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = width;
  desc.Height = height;
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

  HRESULT hr =
      d3d_device_->CreateTexture2D(&desc, nullptr, shared_texture_.put());
  if (FAILED(hr)) return false;

  winrt::com_ptr<IDXGIResource> resource =
      shared_texture_.as<IDXGIResource>();
  hr = resource->GetSharedHandle(&shared_handle_);
  if (FAILED(hr)) {
    shared_texture_ = nullptr;
    shared_handle_ = nullptr;
    return false;
  }
  texture_width_ = width;
  texture_height_ = height;
  return true;
}

void Cs2CapturePlugin::OnFrameArrived(
    const Direct3D11CaptureFramePool& pool) {
  if (!capturing_) return;
  auto frame = pool.TryGetNextFrame();
  if (!frame) return;

  try {
    auto access =
        frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::
                               IDirect3DDxgiInterfaceAccess>();
    winrt::com_ptr<ID3D11Texture2D> frame_texture;
    if (FAILED(access->GetInterface(__uuidof(ID3D11Texture2D),
                                    frame_texture.put_void()))) {
      return;
    }

    const auto content_size = frame.ContentSize();
    const auto width = static_cast<uint32_t>(content_size.Width);
    const auto height = static_cast<uint32_t>(content_size.Height);
    if (width == 0 || height == 0) return;

    if (width != texture_width_ || height != texture_height_) {
      // Window was resized: rebuild both the shared texture and frame pool.
      EnsureSharedTexture(width, height);
      frame_pool_.Recreate(winrt_device_,
                           DirectXPixelFormat::B8G8R8A8UIntNormalized, 2,
                           {static_cast<int32_t>(width),
                            static_cast<int32_t>(height)});
    }

    {
      std::lock_guard<std::mutex> lock(texture_mutex_);
      if (!shared_texture_) return;
      D3D11_TEXTURE2D_DESC frame_desc;
      frame_texture->GetDesc(&frame_desc);
      D3D11_BOX box = {};
      box.right = (frame_desc.Width < width) ? frame_desc.Width : width;
      box.bottom = (frame_desc.Height < height) ? frame_desc.Height : height;
      box.back = 1;
      d3d_context_->CopySubresourceRegion(shared_texture_.get(), 0, 0, 0, 0,
                                          frame_texture.get(), 0, &box);
      d3d_context_->Flush();
    }

    registrar_->texture_registrar()->MarkTextureFrameAvailable(texture_id_);
  } catch (...) {
    // Skip bad frames; the next FrameArrived will retry.
  }
}

void Cs2CapturePlugin::StopCapture() {
  capturing_ = false;
  try {
    if (frame_pool_ && frame_arrived_token_.value != 0) {
      frame_pool_.FrameArrived(frame_arrived_token_);
      frame_arrived_token_ = {};
    }
    if (session_) {
      session_.Close();
      session_ = nullptr;
    }
    if (frame_pool_) {
      frame_pool_.Close();
      frame_pool_ = nullptr;
    }
    item_ = nullptr;
  } catch (...) {
  }
}

}  // namespace

void Cs2CapturePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  Cs2CapturePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
