using Newtonsoft.Json;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation.Runspaces;
using System.Management.Automation;
using System;

namespace Chef
{
    /// <summary>
    /// Provides an class that allows access to Windows PowerShell via the .NET Managed interface.
    /// </summary>
    public partial class PowerShell
    {
        const string EMPTY_JSON_STRING = "{}";

        /// <summary>
        /// Executes a PowerShell script via Windows PowerShell. Requires PowerShell 3.0 or above.
        /// </summary>
        /// <param name="powershellScript">String. Script to execute.</param>
        /// <returns>A string containing either a Json representation of the resultset, or an empty Json object "{}" if no results are returned.</returns>
        public static string ExecuteScript(string powershellScript)
        {
            using (var powershell = System.Management.Automation.PowerShell.Create())
            {
                powershell.AddScript(powershellScript);
                var jsonCommand = new Command("ConvertTo-Json");
                jsonCommand.Parameters.Add("-Compress");
                powershell.Commands.AddCommand(jsonCommand);

                var execution = new Execution();
                var results = new Collection<PSObject>();
                execution.errors = new List<string>();
                execution.verbose = new List<string>();

                try
                {
                    results = powershell.Invoke();
                    switch (results.Count)
                    {
                        case 1:
                            execution.result = results[0].ToString();
                            break;
                        default:
                            execution.result = EMPTY_JSON_STRING;
                            break;
                    }
                }
                catch (RuntimeException runtimeException)
                {
                    execution.result = EMPTY_JSON_STRING;
                    execution.errors.Add(ErrorString($"Runtime exception: {runtimeException.Message}", runtimeException.ErrorRecord));
                }
                finally {
                    foreach (var errorRecord in powershell.Streams.Error)
                    {
                        execution.errors.Add(ErrorString(errorRecord.Exception.Message, errorRecord));
                    }

                    foreach (var verboseRecord in powershell.Streams.Verbose)
                    {
                        execution.verbose.Add(verboseRecord.ToString());
                    }
                }
                return JsonConvert.SerializeObject(execution, new JsonSerializerSettings { DateFormatHandling = DateFormatHandling.IsoDateFormat });
            }
        }

        private static string ErrorString(string message, ErrorRecord errorRecord)
        {
            return errorRecord.InvocationInfo == null
                ? message
                : $"{errorRecord.InvocationInfo.InvocationName}: {message}\n{errorRecord.InvocationInfo.PositionMessage}";
        }
    }
}
