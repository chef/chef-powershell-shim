#pragma once

typedef void * allocation_function(size_t size);

extern "C" {
	//_declspec(dllexport) const wchar_t* ExecuteScript(const char * powershellScript, int timeout = -1);
    _declspec(dllexport) const wchar_t* ExecuteScript(const char* powershellScript, int timeout, allocation_function* ruby_allocate);
}