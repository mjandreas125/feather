#include "clipboard_image.h"

#include <windows.h>
#include <objidl.h>
#include <shellapi.h>
#include <gdiplus.h>

#include <memory>
#include <vector>

#pragma comment(lib, "gdiplus")

namespace {

bool PngEncoder(CLSID* clsid) {
  UINT n = 0, size = 0;
  Gdiplus::GetImageEncodersSize(&n, &size);
  if (size == 0) return false;
  std::vector<uint8_t> buf(size);
  auto* codecs = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buf.data());
  Gdiplus::GetImageEncoders(n, size, codecs);
  for (UINT i = 0; i < n; ++i) {
    if (wcscmp(codecs[i].MimeType, L"image/png") == 0) {
      *clsid = codecs[i].Clsid;
      return true;
    }
  }
  return false;
}

std::string Utf8(const wchar_t* w) {
  int n = ::WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
  std::string s(n > 0 ? n - 1 : 0, '\0');
  if (n > 1) ::WideCharToMultiByte(CP_UTF8, 0, w, -1, &s[0], n, nullptr, nullptr);
  return s;
}

}  // namespace

std::vector<uint8_t> ClipboardImagePng() {
  std::vector<uint8_t> out;
  if (!::IsClipboardFormatAvailable(CF_DIB) && !::IsClipboardFormatAvailable(CF_BITMAP)) return out;
  if (!::OpenClipboard(nullptr)) return out;

  ULONG_PTR token = 0;
  Gdiplus::GdiplusStartupInput input;
  if (Gdiplus::GdiplusStartup(&token, &input, nullptr) != Gdiplus::Ok) {
    ::CloseClipboard();
    return out;
  }
  {
    std::unique_ptr<Gdiplus::Bitmap> bmp;
    if (HANDLE h = ::GetClipboardData(CF_DIB)) {
      // CF_DIB = BITMAPINFO + pixels; GDI+ can read it directly.
      auto* info = static_cast<BITMAPINFO*>(::GlobalLock(h));
      if (info) {
        const BITMAPINFOHEADER& hdr = info->bmiHeader;
        int colors = hdr.biClrUsed ? hdr.biClrUsed : (hdr.biBitCount <= 8 ? (1 << hdr.biBitCount) : 0);
        size_t masks = (hdr.biCompression == BI_BITFIELDS) ? 3 * sizeof(DWORD) : 0;
        const BYTE* bits = reinterpret_cast<const BYTE*>(info) + hdr.biSize + masks + colors * sizeof(RGBQUAD);
        bmp.reset(Gdiplus::Bitmap::FromBITMAPINFO(info, const_cast<BYTE*>(bits)));
        // 32-bit screenshots often carry garbage alpha; draw onto an opaque canvas.
        if (bmp && hdr.biBitCount == 32) {
          auto opaque = std::make_unique<Gdiplus::Bitmap>(bmp->GetWidth(), bmp->GetHeight(), PixelFormat24bppRGB);
          Gdiplus::Graphics g(opaque.get());
          g.DrawImage(bmp.get(), 0, 0, bmp->GetWidth(), bmp->GetHeight());
          bmp = std::move(opaque);
        }
        ::GlobalUnlock(h);
      }
    } else if (HANDLE hb = ::GetClipboardData(CF_BITMAP)) {
      bmp.reset(Gdiplus::Bitmap::FromHBITMAP(static_cast<HBITMAP>(hb), nullptr));
    }
    CLSID png;
    IStream* stream = nullptr;
    if (bmp && bmp->GetLastStatus() == Gdiplus::Ok && PngEncoder(&png) &&
        SUCCEEDED(::CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
      if (bmp->Save(stream, &png, nullptr) == Gdiplus::Ok) {
        STATSTG stat;
        stream->Stat(&stat, STATFLAG_NONAME);
        out.resize(static_cast<size_t>(stat.cbSize.QuadPart));
        LARGE_INTEGER zero = {};
        stream->Seek(zero, STREAM_SEEK_SET, nullptr);
        ULONG read = 0;
        stream->Read(out.data(), static_cast<ULONG>(out.size()), &read);
        out.resize(read);
      }
      stream->Release();
    }
  }
  Gdiplus::GdiplusShutdown(token);
  ::CloseClipboard();
  return out;
}

std::vector<std::string> ClipboardFiles() {
  std::vector<std::string> out;
  if (!::IsClipboardFormatAvailable(CF_HDROP) || !::OpenClipboard(nullptr)) return out;
  if (HANDLE h = ::GetClipboardData(CF_HDROP)) {
    HDROP drop = static_cast<HDROP>(h);
    UINT n = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    for (UINT i = 0; i < n; ++i) {
      wchar_t path[MAX_PATH * 4];
      if (::DragQueryFileW(drop, i, path, MAX_PATH * 4)) out.push_back(Utf8(path));
    }
  }
  ::CloseClipboard();
  return out;
}
