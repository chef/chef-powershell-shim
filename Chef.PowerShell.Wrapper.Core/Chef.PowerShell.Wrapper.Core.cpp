#include "Chef.PowerShell.Wrapper.Core.h"
#include "msclr\marshal.h"

using namespace System;

const wchar_t* ExecuteScript(const char* powershellScript, int timeout)
{
    try {
        String^ wPowerShellScript = gcnew String(powershellScript);
        String^ output = Chef::PowerShell().ExecuteScript(wPowerShellScript, timeout);
        pin_ptr<const wchar_t> result = PtrToStringChars(output);
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
