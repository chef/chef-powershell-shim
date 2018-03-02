using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Management.Automation;
using System.Runtime.InteropServices;
using System.Dynamic;
using Newtonsoft.Json;
using System.Xml;

namespace Chef
{
    /// <summary>
    /// Provides a COM-visible assembly to access Windows PowerShell via the .NET Managed interface.
    /// </summary>
    [Guid("9008CA83-83E4-41FF-9C07-696E2CC47B52")]
    [ComVisible(true)]
    public partial class PowerShell
    {
        const string EMPTY_JSON_STRING = "{}";

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

                var execution = new Execution();
                var results = powerShell.Invoke();

                switch (results.Count)
                {
                    case 1:
                        execution.result = results[0].ToString();
                        break;
                    default:
                        execution.result = EMPTY_JSON_STRING;
                        break;
                }

                execution.errors = new List<string>();
                foreach(var errorRecord in powerShell.Streams.Error)
                {
                    var errorFormat = String.Format("{0}: {1} ({2})",
                        errorRecord.CategoryInfo,
                        errorRecord.Exception.Message,
                        errorRecord.ScriptStackTrace);
                    execution.errors.Add(errorFormat);
                }

                return JsonConvert.SerializeObject(execution);
            }
        }
    }
}
