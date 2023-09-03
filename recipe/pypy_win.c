#include <stdio.h>
#include <Windows.h>

typedef int (*func_type)(int argc, char* argv[]);

int main(int argc, char* argv[]) {
   wchar_t exe_dir[MAX_PATH];
   wchar_t deps_dir[MAX_PATH];
   wchar_t pypy_dll[MAX_PATH];
   GetModuleFileNameW(NULL, exe_dir, MAX_PATH);

   *wcsrchr(exe_dir, L'\\') = L'\0';

   wcscpy(deps_dir, exe_dir);
   wcscat(deps_dir, L"\\Library\\bin\0");
   AddDllDirectory(deps_dir);

   wcscpy(pypy_dll, exe_dir);
   wcscat(pypy_dll, L"\\libpypy" PY_VER L"-c.dll");

   // First, try to load <EXE_DIR>/libpypy<PY_VER>-c.dll with only dependencies in <EXE_DIR>/Library/bin
   HMODULE handle = LoadLibraryExW(pypy_dll, NULL, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR);
   if (handle == NULL) {
     // Second, try to load <EXE_DIR>/libpypy<PY_VER>-c.dll with dependencies found in PATH env variable
     handle = LoadLibraryExW(pypy_dll, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
     if (handle == NULL) {
       printf("Error in loading pypy dll");
       return 1;
     }
   }
   func_type pypy_main_startup = (func_type)GetProcAddress(handle, "pypy_main_startup");
   if (pypy_main_startup == NULL) {
     printf("Error in loading pypy_main_startup");
     return 1;
   }
   return pypy_main_startup(argc, argv);
}
