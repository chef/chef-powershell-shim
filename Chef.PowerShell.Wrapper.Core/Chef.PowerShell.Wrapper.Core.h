#pragma once

extern "C" {
	//_declspec(dllexport) const wchar_t* ExecuteScript(const char* powershellScript, int timeout = -1);
	_declspec(dllexport) const wchar_t* ExecuteScript(const char* powershellScript, void* returnPtr, int memorySize = (10 * 1024 * 1024), int timeout = -1);

}
