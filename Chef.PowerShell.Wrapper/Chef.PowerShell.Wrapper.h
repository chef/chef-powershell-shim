#pragma once

using namespace System;
#using <Chef.PowerShell.dll>

typedef bool store_result_function(const wchar_t *result_string, size_t data_size);

extern "C" {
    _declspec(dllexport) bool ExecuteScript(const char* powershellScript, int timeout, store_result_function* store_result);
}