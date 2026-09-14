#include "stdafx.h"
#include "msclr\marshal.h"
#include "Chef.PowerShell.Wrapper.h"

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
    AssemblyName^ name = gcnew AssemblyName(args->Name);

    // Prefer CHEF_POWERSHELL_BIN when it actually has the assembly, so operators can
    // still point at a different/updated DLL set without moving files around.
    String^ prefix = Environment::GetEnvironmentVariable("CHEF_POWERSHELL_BIN");
    if (prefix) {
        try
        {
            String^ finalPath = Path::Combine(prefix, name->Name + ".dll");
            return Assembly::LoadFrom(finalPath);
        }
        catch (FileNotFoundException^)
        {
            // Fall through -- CHEF_POWERSHELL_BIN may be stale or unrelated to wherever
            // this wrapper assembly actually got loaded from (see fallback below).
        }
    }

    // Fall back to the directory this wrapper assembly itself was loaded from. Without
    // this, an unset/stale/wrong CHEF_POWERSHELL_BIN breaks assembly resolution even
    // though Chef.PowerShell.dll is sitting right next to this wrapper DLL.
    try
    {
        String^ ownDir = Path::GetDirectoryName(Assembly::GetExecutingAssembly()->Location);
        String^ finalPath = Path::Combine(ownDir, name->Name + ".dll");
        return Assembly::LoadFrom(finalPath);
    }
    catch (FileNotFoundException^)
    {
    }

    if (name->Name->ToLower()->StartsWith("chef.powershell")) {
        throw gcnew FileNotFoundException("Unable to load " + name->Name + ".dll. Make sure the file is located in the same directory as this wrapper assembly or in CHEF_POWERSHELL_BIN.");
    }

    return nullptr;
}

// This is the entry point for the DLL. It is called from ruby with the powershell script to execute.
// Note that this is for "PowerShell" (5.1 and earlier) and not "PowerShell Core" (6.0 and later).
// You likely want to make similar changes to the Chef.PowerShell.Core.Wrapper.cpp file.
bool ExecuteScript(const char* powershellScript, int timeout, store_result_function* store_result)
{
    try
    {
        String^ wPowerShellScript = gcnew String(powershellScript, 0, (int)strlen(powershellScript), System::Text::Encoding::UTF8);
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
    catch (Exception^ e)
    {
        // Any managed (.NET) exception thrown from this native function will
        // be raised to the caller as an unintelligible SEHException without this.
        Console::WriteLine(e->ToString());
        throw;
    }
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
