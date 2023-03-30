#include "Chef.PowerShell.Wrapper.Core.h"
#include "msclr\marshal.h"

using namespace System;

const wchar_t* ExecuteScript(const char* powershellScript, int timeout, allocation_function* ruby_allocate)
{
    try {
        String^ wPowerShellScript = gcnew String(powershellScript);
        String^ output = Chef::PowerShell().ExecuteScript(wPowerShellScript, timeout);
        wchar_t *result = (wchar_t*) ruby_allocate(output->Length * 2 + 2);
        pin_ptr<const wchar_t> pinned_result = PtrToStringChars(output);
        wcscpy(result, (const wchar_t*)pinned_result);
        return result;
    }
    catch(Exception^ e){
        // Any managed(.net) exception thrown from this native function will
        // be raised to the user as an unintilligible SEHException. So we provide the
        // courtesy of writing out the original exception details
        Console::WriteLine(e->ToString());
        throw;
    }
}
