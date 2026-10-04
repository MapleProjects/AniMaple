#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shlobj.h>
#include <fstream>
#include <string>
#include <iomanip>

#include "flutter_window.h"
#include "utils.h"

#pragma comment(lib, "shell32.lib")

bool g_is_closing = false;

static LONG WINAPI NativeCrashHandler(EXCEPTION_POINTERS* exceptionInfo) {
  DWORD code = (exceptionInfo && exceptionInfo->ExceptionRecord) ? exceptionInfo->ExceptionRecord->ExceptionCode : 0;
  void* addr = (exceptionInfo && exceptionInfo->ExceptionRecord) ? exceptionInfo->ExceptionRecord->ExceptionAddress : nullptr;

  // Si la aplicación ya está cerrándose o actualizándose, terminar inmediatamente
  // para evitar ventanas de error del sistema operativo (0xC0000005 por descarga de DLLs).
  if (g_is_closing) {
    TerminateProcess(GetCurrentProcess(), code ? code : 0);
    return EXCEPTION_EXECUTE_HANDLER;
  }

  wchar_t localAppData[MAX_PATH];
  std::wstring logPath = L"crash_native.log";
  if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, localAppData))) {
    std::wstring dir = std::wstring(localAppData) + L"\\AniMaple";
    CreateDirectoryW(dir.c_str(), NULL);
    logPath = dir + L"\\crash_native.log";
  }

  std::wofstream log(logPath, std::ios::app);
  if (log.is_open()) {
    SYSTEMTIME st;
    GetLocalTime(&st);
    log << L"[" << st.wYear << L"-" << st.wMonth << L"-" << st.wDay << L" "
        << st.wHour << L":" << st.wMinute << L":" << st.wSecond << L"] "
        << L"Fallo nativo detectado: Codigo 0x" << std::hex << code
        << L" en direccion 0x" << addr << std::endl;
    log.close();
  }

  wchar_t msg[512];
  swprintf_s(msg, 512, L"AniMaple experimento un fallo y se cerro.\nCodigo de excepcion: 0x%08X\n\nEl reporte de fallo se guardo en:\n%s", code, logPath.c_str());
  MessageBoxW(NULL, msg, L"AniMaple - Error inesperado", MB_OK | MB_ICONERROR);

  TerminateProcess(GetCurrentProcess(), code ? code : 1);
  return EXCEPTION_EXECUTE_HANDLER;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  SetUnhandledExceptionFilter(NativeCrashHandler);

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"animaple", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
