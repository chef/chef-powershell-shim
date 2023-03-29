#include "Chef.PowerShell.Wrapper.Core.h"
#include "msclr\marshal.h"

using namespace System;

const wchar_t* ExecuteScript(const char* powershellScript, void *returnPtr, int memorySize, int timeout)
{
    try {
        String^ wPowerShellScript = gcnew String(powershellScript);
        String^ output = Chef::PowerShell().ExecuteScript(wPowerShellScript, timeout);
        pin_ptr<const wchar_t> result = PtrToStringChars(output);

        StreamWriter^ writer = gcnew StreamWriter("C:\\chef-powershell-output.txt", false);

        writer->WriteLine("script::");
        writer->WriteLine(wPowerShellScript);
        writer->WriteLine("output::");
        writer->WriteLine(output);
        writer->Write("returnedString::");

        wcsncpy((wchar_t*) returnPtr, result, memorySize / 2);

        writer->WriteLine(returnPtr);
        writer->Close();
        return (wchar_t*) returnPtr;
    } catch(Exception^ e){
        // Any managed(.net) exception thrown from this native function will
        // be raised to the user as an unintilligible SEHException. So we provide the
        // courtesy of writing out the original exception details
        Console::WriteLine(e->ToString());
        throw;
    }
}

