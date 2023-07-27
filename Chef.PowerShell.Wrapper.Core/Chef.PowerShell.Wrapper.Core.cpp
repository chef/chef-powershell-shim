#include "Chef.PowerShell.Wrapper.Core.h"
#include "msclr\marshal.h"

using namespace System;

// This is the entry point for the DLL. It is called from ruby with the powershell script to execute.
// Note that this is for "PowerShell Core" (6.0 and later) and not "PowerShell" (5.1 and earlier).
// You likely want to make similar changes to the Chef.PowerShell.Wrapper.cpp file.
bool ExecuteScript(const char* powershellScript, int timeout, store_result_function* store_result)
{
    try {
        String^ wPowerShellScript = gcnew String(powershellScript);
        String^ output = Chef::PowerShell().ExecuteScript(wPowerShellScript, timeout);

        pin_ptr<const wchar_t> pinned_result;
        bool success;

        do {
            pinned_result = PtrToStringChars(output);
            // just pass the string length, not the string size including (two byte) \0
            success = store_result(pinned_result, output->Length * sizeof(wchar_t));
        } while(!success);
            
        return success;
    }
    catch(Exception^ e){
        // Any managed(.net) exception thrown from this native function will
        // be raised to the user as an unintelligible SEHException. So we provide the
        // courtesy of writing out the original exception details
        Console::WriteLine(e->ToString());
        throw;
    }
}
