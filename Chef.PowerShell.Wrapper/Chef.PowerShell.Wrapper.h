#pragma once

using namespace System;
#using <Chef.PowerShell.dll>

extern "C" {
	_declspec(dllexport) const char* ExecuteScript(const char* powershellScript);
}
