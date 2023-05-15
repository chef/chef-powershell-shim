#include "Chef.PowerShell.Wrapper.Core.h"
#include "msclr\marshal.h"

using namespace System;
using namespace System::IO;

// This is the entry point for the DLL. It is called from ruby with the powershell script to execute.
// Note that this is for "PowerShell Core" (6.0 and later) and not "PowerShell" (5.1 and earlier).
// You likely want to make similar changes to the Chef.PowerShell.Wrapper.cpp file.
const wchar_t* ExecuteScript(const char* powershellScript, int timeout, allocation_function* ruby_allocate)
{
    try {
        String^ wPowerShellScript = gcnew String(powershellScript);
        String^ output = Chef::PowerShell().ExecuteScript(wPowerShellScript, timeout);

        // Callback to the ruby function passed to us... need to free in ruby.
        wchar_t *result = (wchar_t*) ruby_allocate((output->Length + 1) * sizeof(wchar_t));

        // PtrToStringChars returns interior_ptr<const wchar_t>
        // which can be implicitly cast to pin_ptr<const wchar_t>
        pin_ptr<const wchar_t> pinned_result = PtrToStringChars(output);

        StreamWriter^ writer = gcnew StreamWriter("C:\\chef-powershell-output.txt", false);
        writer->AutoFlush = true;
        writer->WriteLine("script::");
        writer->WriteLine(wPowerShellScript);
        writer->WriteLine("output::");
        writer->WriteLine(output);
        writer->Write("returnedString::");

        // but you have to separately cast to (const wchar_t*) after saving to a
        // pin_ptr<const wchar_t> variable.
        wcscpy(result, (const wchar_t*)pinned_result);

        writer->WriteLine(result);
        writer->WriteLine((long long)result);
        writer->Close();


        // Again, this is our callback allocated memory, so we need to free it in ruby.
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
