using System.Runtime.InteropServices;

namespace Chef
{
    /// <summary>
    /// Provides a COM-visible assembly to access Windows PowerShell via the .NET Managed interface.
    /// </summary>
    public class PowerShell
    {
        /// <summary>
        /// Executes a PowerShell script via Windows PowerShell. Requires PowerShell 3.0 or above.
        /// </summary>
        /// <param name="powershellScript">String. Script to execute.</param>
        /// <param name="disableJsonReturn">Bool. Set to true to disable the appending of ConvertTo-Json to the script.</param>
        /// <returns>A string containing either a Json representation of the resultset, or an empty Json object if no results are returned.</returns>
        [ComVisible(true)]
        public string Execute(string powershellScript, bool disableJsonReturn = false)
        {
            using (var powerShell = System.Management.Automation.PowerShell.Create())
            {
                powerShell.AddScript(powershellScript);
                if (!disableJsonReturn) powerShell.AddCommand("ConvertTo-Json");
                var results = powerShell.Invoke();
                if (results.Count > 0)
                {
                    return results[0].ToString();
                }
                else
                {
                    return "{}";
                }
            }
        }
    }
}
