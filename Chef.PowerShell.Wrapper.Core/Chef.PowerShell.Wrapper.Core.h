#pragma once

extern "C" {
	_declspec(dllexport) const wchar_t* ExecuteScript(const char* powershellScript);
}
