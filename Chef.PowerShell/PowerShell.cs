using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Management.Automation;
using System.Runtime.InteropServices;

namespace Chef
{
    /// <summary>
    /// Provides a COM-visible assembly to access Windows PowerShell via the .NET Managed interface.
    /// </summary>
    [Guid("9008CA83-83E4-41FF-9C07-696E2CC47B52")]
    [ComVisible(true)]
    public class PowerShell
    {
        /// <summary>
        /// Executes a PowerShell script via Windows PowerShell. Requires PowerShell 3.0 or above.
        /// </summary>
        /// <param name="powershellScript">String. Script to execute.</param>
        /// <returns>A string containing either a Json representation of the resultset, or an empty Json object "{}" if no results are returned.</returns>
        
        public string ExecuteScript(string powershellScript)
        {
            using (var powerShell = System.Management.Automation.PowerShell.Create())
            {
                powerShell.AddScript(powershellScript).AddCommand("ConvertTo-Json").AddParameter("Compress");
                var results = powerShell.Invoke();

                // If there were errors read them out the error stream and send to the Console.
                foreach (ErrorRecord err in powerShell.Streams.Error)
                {
                    Console.WriteLine(err.Exception.Message);
                    Console.WriteLine(err.ScriptStackTrace);
                }

                // This method is only ever expected to return a single result
                if (results.Count == 1) return results[0].ToString();
                return "{}";
            }
        }
    }
}
