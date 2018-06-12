#include "stdafx.h"
#include "msclr\marshal.h"
#include "Chef.PowerShell.Wrapper.h"

using namespace System;
using namespace msclr::interop;

const char* ExecuteScript(const char* powershellScript)
{
	Chef::PowerShell chef;
	marshal_context ^ resultContext = gcnew marshal_context();
	const char* result = resultContext->marshal_as<const char*>(chef.ExecuteScript(String(powershellScript).ToString()));
	delete resultContext;
	return result;
}