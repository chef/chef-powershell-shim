using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Management.Automation;
using System.Runtime.InteropServices;
using System.Dynamic;

namespace Chef
{
    public partial class PowerShell
    {
        class Execution
        { 
            public string result;
            public List<string> errors;
        }
    }
}
