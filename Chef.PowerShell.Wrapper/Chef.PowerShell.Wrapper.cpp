#include "stdafx.h"
#include "msclr\marshal.h"
#include "Chef.PowerShell.Wrapper.h"
#include <iostream>

using namespace System;
using namespace System::IO;
using namespace System::Reflection;

// By default, .net will load assemblies from
// the GAC or from the same directory as the running application - ruby.exe in this case.
// In a habitat installation, ruby.exe will exist in its own package and it is not a good practice to copy
// binaries from one package to another. Having our own resolver allows us to customize where .net looks
// for assemblies.
Assembly^ currentDomain_AssemblyResolve(Object^ sender, ResolveEventArgs^ args)
{
    String^ prefix = Environment::GetEnvironmentVariable("CHEF_POWERSHELL_BIN");
    if (prefix) {
        try
        {
            AssemblyName^ name = gcnew AssemblyName(args->Name);
            String^ finalPath = Path::Combine(prefix, name->Name + ".dll");
            Assembly^ retval = Assembly::LoadFrom(finalPath);
            return retval;
        }
        catch (FileNotFoundException^)
        {
        }
    }
    else if (args->Name->ToLower()->StartsWith("chef.powershell")) {
        throw gcnew FileNotFoundException("Unable to load Chef.Powershell.dll. Make sure the file is located in the same directory as ruby.exe or in CHEF_POWERSHELL_BIN.");
    }

    return nullptr;
}

// This is the entry point for the DLL. It is called from ruby with the powershell script to execute.
// Note that this is for "PowerShell" (5.1 and earlier) and not "PowerShell Core" (6.0 and later).
// You likely want to make similiar changes to the Chef.PowerShell.Core.Wrapper.cpp file.
const wchar_t* ExecuteScript(const char* powershellScript, int timeout, allocation_function* ruby_allocate)
{
    String^ wPowerShellScript = gcnew String(powershellScript);
    String^ output = Chef::PowerShell().ExecuteScript(wPowerShellScript, timeout);

    // Callback to the ruby function passed to us... need to free in ruby.
    wchar_t *result = (wchar_t*) ruby_allocate((output->Length + 1) * sizeof(wchar_t));



    StreamWriter^ writer = gcnew StreamWriter("C:\\chef-powershell-output.txt", true);
    writer->AutoFlush = true;
    writer->WriteLine("Chef.PowerShell.Wrapper.cpp");

    writer->WriteLine("script::");
    writer->WriteLine(wPowerShellScript);
    writer->WriteLine("output::");
    writer->WriteLine(output);

    writer->WriteLine("Preparing to output string");

    // PtrToStringChars returns interior_ptr<const wchar_t>
    // which can be implicitly cast to pin_ptr<const wchar_t>
    pin_ptr<const wchar_t> pinned_result = PtrToStringChars(output);

    // but you have to separately cast to (const wchar_t*) after saving to a
    // pin_ptr<const wchar_t> variable.
    wcscpy(result, (const wchar_t*)pinned_result);

    writer->Write("returnedString::");
    writer->WriteLine(gcnew String(result));
    writer->WriteLine((long long)result);
    writer->Close();

    // Again, this is our callback allocated memory, so we need to free it in ruby.
    return result;
}

// This initializes the DLL with an assembly Resolve Handler. Note that we are initializing
// in a global object constructor according to the advice of
// https://docs.microsoft.com/en-us/cpp/dotnet/initialization-of-mixed-assemblies?view=vs-2019.
// One would think that DllMain would be a better location, but having managed code in DllMain
// puts one at risk of "loader lock" dead locks.
struct __declspec(dllexport) Init {
    Init() {
        AppDomain^ currentDomain = AppDomain::CurrentDomain;
        currentDomain->AssemblyResolve += gcnew ResolveEventHandler(currentDomain_AssemblyResolve);
    }
};

#pragma unmanaged
Init obj;
