#include "nx_desktop.h"

#include <dwmapi.h>
#include <shellapi.h>
#include <commdlg.h>

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cctype>
#include <cstring>
using std::max;
using std::min;
#include <objidl.h>
#include <gdiplus.h>

#include "resource.h"

std::string g_nx_initial_url;

bool NxIsDialUrl(const std::string& s) {
  std::string l = s.substr(0, 7);
  for (auto& ch : l) ch = (char)tolower((unsigned char)ch);
  return l.rfind("tel:", 0) == 0 || l.rfind("sip:", 0) == 0 || l.rfind("sips:", 0) == 0 || l.rfind("callto:", 0) == 0 || l.rfind("softsall", 0) == 0;
}

namespace {

constexpr wchar_t kUrlProgId[] = L"Noryxs.Url";
constexpr wchar_t kAppKey[] = L"Software\\NORYXS\\Capabilities";

constexpr UINT kTrayMessage = WM_APP + 41;
constexpr UINT kTrayId = 1;
constexpr UINT kMenuOpen = 1001;
constexpr UINT kMenuQuit = 1002;
constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"NORYXS Terminal";
constexpr wchar_t kCardClass[] = L"NORYXS_CALL_CARD";

// Colores NORYXS (mismos que lib/ui/theme.dart)
const Gdiplus::Color kGold(255, 0xC5, 0xA0, 0x59);
const Gdiplus::Color kGoldDark(255, 0x9A, 0x7B, 0x3E);
const Gdiplus::Color kGoldLight(255, 0xFA, 0xF5, 0xEB);
const Gdiplus::Color kCharcoal(255, 0x18, 0x18, 0x1B);
const Gdiplus::Color kSurface(255, 0xF9, 0xFA, 0xFB);
const Gdiplus::Color kBorder(255, 0xE5, 0xE7, 0xEB);
const Gdiplus::Color kGray(255, 0x6B, 0x72, 0x80);
const Gdiplus::Color kEmerald(255, 0x05, 0x96, 0x69);
const Gdiplus::Color kRed50(255, 0xFE, 0xF2, 0xF2);
const Gdiplus::Color kRed200(255, 0xFE, 0xCA, 0xCA);
const Gdiplus::Color kRed700(255, 0xB9, 0x1C, 0x1C);

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), &w[0], n);
  return w;
}

std::wstring ExePath() {
  wchar_t buf[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, buf, MAX_PATH);
  return std::wstring(buf, n);
}

std::wstring ExeDir() {
  std::wstring p = ExePath();
  size_t i = p.find_last_of(L"\\/");
  return i == std::wstring::npos ? p : p.substr(0, i);
}

const flutter::EncodableValue* Find(const flutter::EncodableMap& m, const char* key) {
  auto it = m.find(flutter::EncodableValue(std::string(key)));
  return it == m.end() ? nullptr : &it->second;
}

std::string GetStr(const flutter::EncodableMap& m, const char* key) {
  auto v = Find(m, key);
  if (v) {
    if (auto s = std::get_if<std::string>(v)) return *s;
  }
  return std::string();
}

int GetInt(const flutter::EncodableMap& m, const char* key, int def) {
  auto v = Find(m, key);
  if (v) {
    if (auto i = std::get_if<int32_t>(v)) return *i;
    if (auto l = std::get_if<int64_t>(v)) return (int)*l;
  }
  return def;
}

bool GetBool(const flutter::EncodableMap& m, const char* key, bool def) {
  auto v = Find(m, key);
  if (v) {
    if (auto b = std::get_if<bool>(v)) return *b;
  }
  return def;
}

double GetDouble(const flutter::EncodableMap& m, const char* key, double def) {
  auto v = Find(m, key);
  if (v) {
    if (auto d = std::get_if<double>(v)) return *d;
    if (auto i = std::get_if<int32_t>(v)) return *i;
  }
  return def;
}

void RoundRectPath(Gdiplus::GraphicsPath& p, Gdiplus::REAL x, Gdiplus::REAL y, Gdiplus::REAL w,
                   Gdiplus::REAL h, Gdiplus::REAL r) {
  Gdiplus::REAL d = r * 2;
  p.AddArc(x, y, d, d, 180, 90);
  p.AddArc(x + w - d, y, d, d, 270, 90);
  p.AddArc(x + w - d, y + h - d, d, d, 0, 90);
  p.AddArc(x, y + h - d, d, d, 90, 90);
  p.CloseFigure();
}

}  // namespace

// ---------------------------------------------------------------------------
// Tarjeta flotante (ventana emergente nativa, sin activar, siempre encima)
// ---------------------------------------------------------------------------

class NxCallCard {
 public:
  explicit NxCallCard(NxDesktop* owner) : owner_(owner) {
    Gdiplus::GdiplusStartupInput in;
    Gdiplus::GdiplusStartup(&gdiplus_token_, &in, nullptr);
    // Fuentes de la app (Inter / JetBrains Mono) incluidas en los assets de Flutter
    std::wstring fonts = ExeDir() + L"\\data\\flutter_assets\\assets\\fonts\\";
    for (const wchar_t* f : {L"Inter-Regular.ttf", L"Inter-Bold.ttf", L"JetBrainsMono-Regular.ttf"}) {
      fonts_.AddFontFile((fonts + f).c_str());
    }
    WNDCLASSEXW wc = {sizeof(wc)};
    wc.style = CS_DROPSHADOW;
    wc.lpfnWndProc = &NxCallCard::WndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = kCardClass;
    RegisterClassExW(&wc);
  }

  ~NxCallCard() {
    if (hwnd_) DestroyWindow(hwnd_);
    Gdiplus::GdiplusShutdown(gdiplus_token_);
  }

  void Apply(const flutter::EncodableMap& a, int queued) {
    call_id_ = GetInt(a, "callId", call_id_);
    line_ = Utf8ToWide(GetStr(a, "lineBadge"));
    name_ = Utf8ToWide(GetStr(a, "name"));
    number_ = Utf8ToWide(GetStr(a, "number"));
    initials_ = Utf8ToWide(GetStr(a, "initials"));
    note_ = Utf8ToWide(GetStr(a, "note"));
    geo_ = Utf8ToWide(GetStr(a, "geo"));
    muted_ = GetBool(a, "muted", false);
    queued_ = queued;
    if (hwnd_) InvalidateRect(hwnd_, nullptr, FALSE);
  }

  void Show() {
    if (!hwnd_) Create();
    UINT dpi = GetDpiForWindow(hwnd_);
    scale_ = dpi / 96.0f;
    int w = (int)(kWidth * scale_), h = (int)(kHeight * scale_);
    RECT work;
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    int x = work.right - w - (int)(16 * scale_);
    int y = work.top + (int)(16 * scale_);
    SetWindowPos(hwnd_, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(hwnd_, nullptr, FALSE);
  }

  void Hide() {
    if (hwnd_) ShowWindow(hwnd_, SW_HIDE);
  }

  int call_id() const { return call_id_; }

 private:
  static constexpr float kWidth = 390;
  static constexpr float kHeight = 200;

  void Create() {
    hwnd_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kCardClass,
                            L"NORYXS Terminal \u00b7 Llamada entrante", WS_POPUP, 0, 0, 10, 10, nullptr,
                            nullptr, GetModuleHandle(nullptr), this);
    // Esquinas redondeadas de Windows 11 (en Windows 10 se ignora)
    DWORD pref = 2;  // DWMWCP_ROUND
    DwmSetWindowAttribute(hwnd_, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */, &pref, sizeof(pref));
  }

  Gdiplus::Font* MakeFont(const wchar_t* family, float size, int style) {
    Gdiplus::FontFamily ff(family, &fonts_);
    if (ff.GetLastStatus() != Gdiplus::Ok) {
      Gdiplus::FontFamily sys(L"Segoe UI");
      return new Gdiplus::Font(&sys, size * scale_, style, Gdiplus::UnitPixel);
    }
    return new Gdiplus::Font(&ff, size * scale_, style, Gdiplus::UnitPixel);
  }

  void PaintText(Gdiplus::Graphics& g, const std::wstring& t, Gdiplus::Font* f, const Gdiplus::Color& c,
                float x, float y, float w, float h, Gdiplus::StringAlignment align = Gdiplus::StringAlignmentNear) {
    Gdiplus::SolidBrush b(c);
    Gdiplus::StringFormat sf;
    sf.SetAlignment(align);
    sf.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    sf.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
    sf.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
    Gdiplus::RectF r(x * scale_, y * scale_, w * scale_, h * scale_);
    g.DrawString(t.c_str(), (INT)t.size(), f, r, &sf, &b);
  }

  void FillRound(Gdiplus::Graphics& g, float x, float y, float w, float h, float r, const Gdiplus::Color& fill,
                 const Gdiplus::Color* stroke = nullptr) {
    Gdiplus::GraphicsPath p;
    RoundRectPath(p, x * scale_, y * scale_, w * scale_, h * scale_, r * scale_);
    Gdiplus::SolidBrush b(fill);
    g.FillPath(&b, &p);
    if (stroke) {
      Gdiplus::Pen pen(*stroke, 1.0f * scale_);
      g.DrawPath(&pen, &p);
    }
  }

  void Paint(HDC hdc) {
    RECT rc;
    GetClientRect(hwnd_, &rc);
    Gdiplus::Bitmap buf(rc.right, rc.bottom, PixelFormat32bppARGB);
    Gdiplus::Graphics g(&buf);
    g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    g.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);
    g.Clear(Gdiplus::Color(255, 255, 255, 255));
    const float W = kWidth, P = 16;

    // Marco en oro
    {
      Gdiplus::Pen pen(Gdiplus::Color(150, 0xC5, 0xA0, 0x59), 1.0f * scale_);
      g.DrawRectangle(&pen, 0.0f, 0.0f, rc.right - 1.0f, rc.bottom - 1.0f);
    }

    std::unique_ptr<Gdiplus::Font> bold11(MakeFont(L"Inter", 11, Gdiplus::FontStyleBold));
    std::unique_ptr<Gdiplus::Font> reg10(MakeFont(L"Inter", 10, Gdiplus::FontStyleRegular));
    std::unique_ptr<Gdiplus::Font> bold16(MakeFont(L"Inter", 16, Gdiplus::FontStyleBold));
    std::unique_ptr<Gdiplus::Font> reg11(MakeFont(L"Inter", 11, Gdiplus::FontStyleRegular));
    std::unique_ptr<Gdiplus::Font> reg105(MakeFont(L"Inter", 10.5f, Gdiplus::FontStyleRegular));
    std::unique_ptr<Gdiplus::Font> bold12(MakeFont(L"Inter", 12, Gdiplus::FontStyleBold));
    std::unique_ptr<Gdiplus::Font> mono12(MakeFont(L"JetBrains Mono", 12, Gdiplus::FontStyleRegular));
    std::unique_ptr<Gdiplus::Font> mono10(MakeFont(L"JetBrains Mono", 10, Gdiplus::FontStyleBold));

    // Cabecera: campana, marca, línea
    FillRound(g, P, P, 24, 24, 8, kCharcoal);
    {
      Gdiplus::FontFamily icons(L"Segoe MDL2 Assets");
      Gdiplus::Font icon(&icons, 11 * scale_, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
      PaintText(g, L"\xEA8F", &icon, kGold, P, P, 24, 24, Gdiplus::StringAlignmentCenter);
    }
    PaintText(g, L"NORYXS SIP", bold11.get(), kCharcoal, P + 32, P, 90, 24);
    PaintText(g, L"\x2022 Llamada entrante", reg10.get(), kGray, P + 118, P, 120, 24);
    if (!line_.empty()) {
      float bw = 12 + 6.5f * (float)min<size_t>(line_.size(), 16);
      Gdiplus::Color b(102, 0xA4, 0x49, 0x3D);
      FillRound(g, W - P - bw, P + 3, bw, 18, 9, kGoldLight, &b);
      PaintText(g, line_, mono10.get(), kGoldDark, W - P - bw, P + 3, bw, 18, Gdiplus::StringAlignmentCenter);
    }
    {
      Gdiplus::Pen sep(kBorder, 1.0f * scale_);
      g.DrawLine(&sep, P * scale_, (P + 34) * scale_, (W - P) * scale_, (P + 34) * scale_);
    }

    // Llamante
    const float cy = P + 46;
    FillRound(g, P, cy, 48, 48, 16, kSurface, &kBorder);
    PaintText(g, initials_.empty() ? L"\x260E" : initials_, bold16.get(), kCharcoal, P, cy, 48, 48,
             Gdiplus::StringAlignmentCenter);
    {
      Gdiplus::SolidBrush white(Gdiplus::Color(255, 255, 255, 255));
      Gdiplus::SolidBrush gold(kGold);
      g.FillEllipse(&white, (P + 38) * scale_, (cy + 38) * scale_, 16 * scale_, 16 * scale_);
      g.FillEllipse(&gold, (P + 39) * scale_, (cy + 39) * scale_, 14 * scale_, 14 * scale_);
    }
    const float tx = P + 62, tw = W - tx - P;
    float ty = cy - 2;
    PaintText(g, name_, bold16.get(), kCharcoal, tx, ty, tw, 21);
    ty += 21;
    if (!number_.empty()) { PaintText(g, number_, mono12.get(), kGray, tx, ty, tw, 16); ty += 16; }
    if (!geo_.empty()) { PaintText(g, geo_, reg105.get(), kGray, tx, ty, tw, 15); ty += 15; }
    std::wstring note = note_;
    if (queued_ > 0) note += L" \x00B7 +" + std::to_wstring(queued_) + L" en cola";
    PaintText(g, note, reg11.get(), kGoldDark, tx, ty + 2, tw, 15);

    // Acciones
    const float by = kHeight - P - 36, gap = 8;
    const float unit = (W - 2 * P - 2 * gap) / 12;
    btn_answer_ = {P, by, unit * 6, 36};
    btn_mute_ = {P + unit * 6 + gap, by, unit * 3, 36};
    btn_reject_ = {P + unit * 9 + 2 * gap, by, unit * 3, 36};
    FillRound(g, btn_answer_.X, by, btn_answer_.Width, 36, 12, kEmerald);
    PaintText(g, L"\x260E  Contestar", bold12.get(), Gdiplus::Color(255, 255, 255, 255), btn_answer_.X, by,
             btn_answer_.Width, 36, Gdiplus::StringAlignmentCenter);
    FillRound(g, btn_mute_.X, by, btn_mute_.Width, 36, 12, kSurface, &kBorder);
    PaintText(g, muted_ ? L"Silenciado" : L"Silenciar", reg11.get(),
             muted_ ? Gdiplus::Color(255, 0x9C, 0xA3, 0xAF) : Gdiplus::Color(255, 0x45, 0x45, 0x45), btn_mute_.X,
             by, btn_mute_.Width, 36, Gdiplus::StringAlignmentCenter);
    FillRound(g, btn_reject_.X, by, btn_reject_.Width, 36, 12, kRed50, &kRed200);
    PaintText(g, L"Rechazar", reg11.get(), kRed700, btn_reject_.X, by, btn_reject_.Width, 36,
             Gdiplus::StringAlignmentCenter);

    Gdiplus::Graphics screen(hdc);
    screen.DrawImage(&buf, 0, 0);
  }

  const char* HitButton(int px, int py) const {
    float x = px / scale_, y = py / scale_;
    if (btn_answer_.Contains(x, y)) return "answer";
    if (btn_mute_.Contains(x, y) && !muted_) return "mute";
    if (btn_reject_.Contains(x, y)) return "reject";
    return nullptr;
  }

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    NxCallCard* self;
    if (msg == WM_NCCREATE) {
      self = static_cast<NxCallCard*>(reinterpret_cast<CREATESTRUCT*>(lp)->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    } else {
      self = reinterpret_cast<NxCallCard*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
    }
    if (!self) return DefWindowProc(hwnd, msg, wp, lp);
    switch (msg) {
      case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        self->Paint(hdc);
        EndPaint(hwnd, &ps);
        return 0;
      }
      case WM_ERASEBKGND:
        return 1;
      case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
      case WM_NCHITTEST: {
        // Fuera de los botones la tarjeta se arrastra
        POINT pt = {(short)LOWORD(lp), (short)HIWORD(lp)};
        ScreenToClient(hwnd, &pt);
        return self->HitButton(pt.x, pt.y) ? HTCLIENT : HTCAPTION;
      }
      case WM_SETCURSOR:
        if (LOWORD(lp) == HTCLIENT) {
          SetCursor(LoadCursor(nullptr, IDC_HAND));
          return TRUE;
        }
        break;
      case WM_LBUTTONUP: {
        const char* action = self->HitButton((short)LOWORD(lp), (short)HIWORD(lp));
        if (action) self->owner_->CardAction(action, self->call_id_, strcmp(action, "answer") == 0);
        return 0;
      }
      case WM_DPICHANGED:
        self->scale_ = HIWORD(wp) / 96.0f;
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
    }
    return DefWindowProc(hwnd, msg, wp, lp);
  }

  NxDesktop* owner_;
  HWND hwnd_ = nullptr;
  ULONG_PTR gdiplus_token_ = 0;
  Gdiplus::PrivateFontCollection fonts_;
  float scale_ = 1.0f;
  int call_id_ = -1;
  int queued_ = 0;
  bool muted_ = false;
  std::wstring line_, name_, number_, initials_, note_, geo_;
  Gdiplus::RectF btn_answer_, btn_mute_, btn_reject_;
};

// ---------------------------------------------------------------------------
// NxDesktop
// ---------------------------------------------------------------------------

NxDesktop::NxDesktop(HWND window, flutter::BinaryMessenger* messenger) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "noryxs/window", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) { OnMethodCall(call, std::move(result)); });
  card_ = std::make_unique<NxCallCard>(this);
  taskbar_created_msg_ = RegisterWindowMessageW(L"TaskbarCreated");
  if (!g_nx_initial_url.empty()) pending_urls_.push_back(g_nx_initial_url);
  // Enlaces noryxs: (configuración de puestos): esquema propio, sin pedir nada al usuario
  {
    std::wstring cls = L"Software\\Classes\\noryxs";
    std::wstring cmd = L"\"" + ExePath() + L"\" \"%1\"";
    HKEY key;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, cls.c_str(), 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
      const wchar_t desc[] = L"URL NORYXS";
      RegSetValueExW(key, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(desc), sizeof(desc));
      RegSetValueExW(key, L"URL Protocol", 0, REG_SZ, reinterpret_cast<const BYTE*>(L""), sizeof(wchar_t));
      RegCloseKey(key);
    }
    HKEY ck;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, (cls + L"\\shell\\open\\command").c_str(), 0, nullptr, 0, KEY_SET_VALUE, nullptr, &ck,
                        nullptr) == ERROR_SUCCESS) {
      RegSetValueExW(ck, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(cmd.c_str()), (DWORD)((cmd.size() + 1) * sizeof(wchar_t)));
      RegCloseKey(ck);
    }
  }
  AddTrayIcon();
}

NxDesktop::~NxDesktop() {
  RemoveTrayIcon();
}

void NxDesktop::OnMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  static const flutter::EncodableMap kEmpty;
  const flutter::EncodableMap* args = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
  const flutter::EncodableMap& a = args ? *args : kEmpty;
  const std::string& m = call.method_name();

  if (m == "incomingCall") {
    IncomingCall(a);
  } else if (m == "updateCall") {
    UpdateCall(a);
  } else if (m == "callHandled") {
    CallHandled(a);
  } else if (m == "setSidePanel") {
    SetSidePanel(GetBool(a, "open", false), GetDouble(a, "width", 320));
  } else if (m == "startDrag") {
    ReleaseCapture();
    SendMessage(window_, WM_NCLBUTTONDOWN, HTCAPTION, 0);
  } else if (m == "attention") {
    FLASHWINFO fi = {sizeof(fi), window_, FLASHW_ALL | FLASHW_TIMERNOFG, 0, 0};
    FlashWindowEx(&fi);
  } else if (m == "setLaunchAtLogin") {
    bool enabled = GetBool(a, "enabled", true);
    HKEY key;
    bool ok = false;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key) == ERROR_SUCCESS) {
      if (enabled) {
        std::wstring cmd = L"\"" + ExePath() + L"\"";
        ok = RegSetValueExW(key, kRunValue, 0, REG_SZ, reinterpret_cast<const BYTE*>(cmd.c_str()),
                            (DWORD)((cmd.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS;
      } else {
        LONG r = RegDeleteValueW(key, kRunValue);
        ok = r == ERROR_SUCCESS || r == ERROR_FILE_NOT_FOUND;
      }
      RegCloseKey(key);
    }
    result->Success(flutter::EncodableValue(ok));
    return;
  } else if (m == "pickFile" || m == "saveFile") {
    // Selector de ficheros nativo (CSV de habitaciones, configuración de puestos)
    wchar_t file[MAX_PATH] = {0};
    std::wstring name = Utf8ToWide(GetStr(a, "name"));
    if (m == "saveFile") wcsncpy_s(file, name.c_str(), _TRUNCATE);
    std::wstring title = Utf8ToWide(GetStr(a, "title"));
    OPENFILENAMEW ofn = {sizeof(ofn)};
    ofn.hwndOwner = window_;
    ofn.lpstrFilter = L"Todos los ficheros\0*.*\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrTitle = title.empty() ? nullptr : title.c_str();
    ofn.Flags = OFN_EXPLORER | OFN_NOCHANGEDIR | (m == "saveFile" ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);
    BOOL ok = m == "saveFile" ? GetSaveFileNameW(&ofn) : GetOpenFileNameW(&ofn);
    if (!ok) {
      result->Success();
      return;
    }
    int n = WideCharToMultiByte(CP_UTF8, 0, file, -1, nullptr, 0, nullptr, nullptr);
    std::string path(n > 0 ? n - 1 : 0, '\0');
    if (n > 1) WideCharToMultiByte(CP_UTF8, 0, file, -1, &path[0], n, nullptr, nullptr);
    result->Success(flutter::EncodableValue(path));
    return;
  } else if (m == "setHotkeys") {
    SetHotkeys(GetBool(a, "enabled", true));
  } else if (m == "setMediaSession") {
    SetMediaKey(GetBool(a, "active", false));
  } else if (m == "urlHandlerReady") {
    url_ready_ = true;
    flutter::EncodableList list;
    for (const auto& u : pending_urls_) list.push_back(flutter::EncodableValue(u));
    if (!pending_urls_.empty()) BringToFront();
    pending_urls_.clear();
    result->Success(flutter::EncodableValue(list));
    return;
  } else if (m == "setDefaultDialer") {
    result->Success(flutter::EncodableValue(SetDefaultDialer()));
    return;
  } else if (m == "isDefaultDialer") {
    result->Success(flutter::EncodableValue(IsDefaultDialer()));
    return;
  } else if (m == "getLaunchAtLogin") {
    bool on = RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ, nullptr, nullptr, nullptr) ==
              ERROR_SUCCESS;
    result->Success(flutter::EncodableValue(on));
    return;
  }
  result->Success();
}

bool NxDesktop::UserIsLookingAtTerminal() const {
  return IsWindowVisible(window_) && !IsIconic(window_) && GetForegroundWindow() == window_;
}

void NxDesktop::IncomingCall(const flutter::EncodableMap& a) {
  int id = GetInt(a, "callId", -1);
  ringing_[id] = a;
  if (std::find(ringing_order_.begin(), ringing_order_.end(), id) == ringing_order_.end()) ringing_order_.push_back(id);

  // Contexto A (terminal a la vista): basta la franja integrada de Flutter
  if (UserIsLookingAtTerminal()) return;

  FLASHWINFO fi = {sizeof(fi), window_, FLASHW_TRAY | FLASHW_TIMERNOFG, 0, 0};
  FlashWindowEx(&fi);
  if (GetBool(a, "card", true)) {
    RefreshCard();
    card_->Show();
  }
}

void NxDesktop::UpdateCall(const flutter::EncodableMap& a) {
  int id = GetInt(a, "callId", -1);
  if (ringing_.find(id) == ringing_.end()) return;
  ringing_[id] = a;
  if (card_->call_id() == id) RefreshCard();
}

void NxDesktop::CallHandled(const flutter::EncodableMap& a) {
  int id = GetInt(a, "callId", -1);
  ringing_.erase(id);
  ringing_order_.erase(std::remove(ringing_order_.begin(), ringing_order_.end(), id), ringing_order_.end());
  if (ringing_order_.empty()) {
    card_->Hide();
  } else {
    RefreshCard();
  }
}

void NxDesktop::RefreshCard() {
  if (ringing_order_.empty()) return;
  card_->Apply(ringing_[ringing_order_.front()], (int)ringing_order_.size() - 1);
}

void NxDesktop::CardAction(const char* action, int call_id, bool bring_front) {
  channel_->InvokeMethod("notificationAction",
                         std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                             {flutter::EncodableValue("action"), flutter::EncodableValue(std::string(action))},
                             {flutter::EncodableValue("callId"), flutter::EncodableValue(call_id)},
                         }));
  if (bring_front) {
    card_->Hide();
    BringToFront();
  }
}

void NxDesktop::SetSidePanel(bool open, double width) {
  if (open == side_panel_open_) return;
  side_panel_open_ = open;
  side_panel_width_ = (int)width;
  // Maximizada: no se cambia el tamaño; la interfaz superpone el panel
  if (IsZoomed(window_)) return;
  RECT r;
  GetWindowRect(window_, &r);
  int delta = (int)(width * GetDpiForWindow(window_) / 96.0);
  int w = (r.right - r.left) + (open ? delta : -delta);
  int x = r.left;
  MONITORINFO mi = {sizeof(mi)};
  if (GetMonitorInfo(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &mi) && x + w > mi.rcWork.right) {
    x = max((int)mi.rcWork.left, (int)mi.rcWork.right - w);
  }
  SetWindowPos(window_, nullptr, x, r.top, w, r.bottom - r.top, SWP_NOZORDER | SWP_NOACTIVATE);
}

void NxDesktop::DeliverUrl(const std::string& url) {
  if (!url_ready_) {
    pending_urls_.push_back(url);
    return;
  }
  channel_->InvokeMethod("openUrl", std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                                        {flutter::EncodableValue("url"), flutter::EncodableValue(url)}}));
  BringToFront();
}

namespace {
bool SetRegString(HKEY root, const std::wstring& path, const wchar_t* name, const std::wstring& value) {
  HKEY key;
  if (RegCreateKeyExW(root, path.c_str(), 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) return false;
  LONG r = RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
                          (DWORD)((value.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  return r == ERROR_SUCCESS;
}
}  // namespace

// Registra NORYXS como aplicación capaz de abrir tel:/sip:/callto: y abre la página de
// aplicaciones predeterminadas (desde Windows 8 el usuario debe confirmar la elección).
bool NxDesktop::SetDefaultDialer() {
  std::wstring cls = std::wstring(L"Software\\Classes\\") + kUrlProgId;
  std::wstring cmd = L"\"" + ExePath() + L"\" \"%1\"";
  bool ok = SetRegString(HKEY_CURRENT_USER, cls, nullptr, L"URL NORYXS") &&
            SetRegString(HKEY_CURRENT_USER, cls, L"URL Protocol", L"") &&
            SetRegString(HKEY_CURRENT_USER, cls + L"\\DefaultIcon", nullptr, ExePath() + L",0") &&
            SetRegString(HKEY_CURRENT_USER, cls + L"\\shell\\open\\command", nullptr, cmd) &&
            SetRegString(HKEY_CURRENT_USER, kAppKey, L"ApplicationName", L"NORYXS") &&
            SetRegString(HKEY_CURRENT_USER, kAppKey, L"ApplicationDescription", L"Tel\u00e9fono IP") &&
            SetRegString(HKEY_CURRENT_USER, std::wstring(kAppKey) + L"\\URLAssociations", L"tel", kUrlProgId) &&
            SetRegString(HKEY_CURRENT_USER, std::wstring(kAppKey) + L"\\URLAssociations", L"sip", kUrlProgId) &&
            SetRegString(HKEY_CURRENT_USER, std::wstring(kAppKey) + L"\\URLAssociations", L"callto", kUrlProgId) &&
            SetRegString(HKEY_CURRENT_USER, L"Software\\RegisteredApplications", L"NORYXS", kAppKey);
  if (ok) {
    ShellExecuteW(nullptr, L"open", L"ms-settings:defaultapps?registeredAppUser=NORYXS", nullptr, nullptr, SW_SHOWNORMAL);
  }
  return ok;
}

bool NxDesktop::IsDefaultDialer() const {
  wchar_t prog[128] = {0};
  DWORD size = sizeof(prog);
  if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\Shell\\Associations\\UrlAssociations\\tel\\UserChoice",
                   L"ProgId", RRF_RT_REG_SZ, nullptr, prog, &size) != ERROR_SUCCESS) {
    return false;
  }
  return wcscmp(prog, kUrlProgId) == 0;
}

// Atajos globales Ctrl+Alt+A / H / M (contestar, colgar, silenciar).
void NxDesktop::SetHotkeys(bool on) {
  if (hotkeys_) {
    for (int id = 1; id <= 3; ++id) UnregisterHotKey(window_, id);
    hotkeys_ = false;
  }
  if (!on) return;
  const UINT mods = MOD_CONTROL | MOD_ALT | MOD_NOREPEAT;
  RegisterHotKey(window_, 1, mods, 'A');
  RegisterHotKey(window_, 2, mods, 'H');
  RegisterHotKey(window_, 3, mods, 'M');
  hotkeys_ = true;
}

// Botón de los cascos (reproducir/pausa): solo mientras hay una llamada sonando o en curso,
// para no quitarle el control de la música al resto de apps.
void NxDesktop::SetMediaKey(bool on) {
  if (on == media_key_) return;
  if (on) {
    media_key_ = RegisterHotKey(window_, 10, 0, VK_MEDIA_PLAY_PAUSE) != FALSE;
  } else {
    UnregisterHotKey(window_, 10);
    media_key_ = false;
  }
}

void NxDesktop::BringToFront() {
  if (IsIconic(window_)) ShowWindow(window_, SW_RESTORE);
  else ShowWindow(window_, SW_SHOW);
  SetForegroundWindow(window_);
}

void NxDesktop::Quit() {
  quitting_ = true;
  card_->Hide();
  RemoveTrayIcon();
  PostMessage(window_, WM_CLOSE, 0, 0);
}

void NxDesktop::AddTrayIcon() {
  NOTIFYICONDATAW nid = {sizeof(nid)};
  nid.hWnd = window_;
  nid.uID = kTrayId;
  nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid.uCallbackMessage = kTrayMessage;
  nid.hIcon = static_cast<HICON>(LoadImageW(GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
                                            GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0));
  wcscpy_s(nid.szTip, L"NORYXS Terminal");
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &nid) == TRUE;
}

void NxDesktop::RemoveTrayIcon() {
  if (!tray_added_) return;
  NOTIFYICONDATAW nid = {sizeof(nid)};
  nid.hWnd = window_;
  nid.uID = kTrayId;
  Shell_NotifyIconW(NIM_DELETE, &nid);
  tray_added_ = false;
}

void NxDesktop::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kMenuOpen, L"Abrir NORYXS Terminal");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuQuit, L"Salir de NORYXS Terminal");
  POINT pt;
  GetCursorPos(&pt);
  SetForegroundWindow(window_);  // necesario para que el menú se cierre al pulsar fuera
  UINT cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, pt.x, pt.y, 0, window_, nullptr);
  DestroyMenu(menu);
  if (cmd == kMenuOpen) BringToFront();
  if (cmd == kMenuQuit) Quit();
}

std::optional<LRESULT> NxDesktop::HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == taskbar_created_msg_ && taskbar_created_msg_ != 0) {
    // Explorer se ha reiniciado: volver a poner el icono de la bandeja
    tray_added_ = false;
    AddTrayIcon();
    return 0;
  }
  switch (message) {
    case WM_CLOSE:
      // Como un teléfono: cerrar la ventana la oculta y NORYXS Terminal sigue recibiendo llamadas
      if (!quitting_) {
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;
    case kTrayMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          BringToFront();
          return 0;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          return 0;
      }
      return 0;
    case WM_HOTKEY: {
      const char* action = wparam == 1 ? "answer" : wparam == 2 ? "hangup" : wparam == 3 ? "mute" : wparam == 10 ? "headset" : nullptr;
      if (action) {
        channel_->InvokeMethod("hotkey", std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                                             {flutter::EncodableValue("action"), flutter::EncodableValue(std::string(action))}}));
      }
      return 0;
    }
    case WM_COPYDATA: {
      // Una segunda instancia (abierta por un enlace tel:/sip:) nos pasa su enlace
      auto* cds = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (cds && cds->dwData == kNxUrlCopyData && cds->lpData) {
        DeliverUrl(std::string(static_cast<const char*>(cds->lpData), cds->cbData));
        return TRUE;
      }
      break;
    }
    case WM_POWERBROADCAST:
      if (wparam == PBT_APMRESUMEAUTOMATIC) {
        // Tras suspender el equipo: rehacer transportes y registros SIP
        channel_->InvokeMethod("wake", nullptr);
      }
      break;
    case WM_GETMINMAXINFO: {
      // Como en macOS: redimensionable con mínimo 440×720 (+ panel de cola si está abierto)
      UINT dpi = GetDpiForWindow(hwnd);
      RECT adj = {0, 0, MulDiv(side_panel_open_ ? 440 + side_panel_width_ : 440, dpi, 96), MulDiv(720, dpi, 96)};
      AdjustWindowRectExForDpi(&adj, (DWORD)GetWindowLong(hwnd, GWL_STYLE), FALSE,
                               (DWORD)GetWindowLong(hwnd, GWL_EXSTYLE), dpi);
      auto* mmi = reinterpret_cast<MINMAXINFO*>(lparam);
      mmi->ptMinTrackSize.x = adj.right - adj.left;
      mmi->ptMinTrackSize.y = adj.bottom - adj.top;
      return 0;
    }
    case WM_ACTIVATE:
      // Al volver al terminal, la tarjeta sobra: la franja de Flutter ya avisa
      if (LOWORD(wparam) != WA_INACTIVE) card_->Hide();
      break;
  }
  return std::nullopt;
}
