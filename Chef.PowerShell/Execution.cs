using System.Collections.Generic;

namespace Chef
{
    public partial class PowerShell
    {
        /// <summary>
        /// Object that contains the execution result and any errors.
        /// </summary>
        public class Execution
        { 
            /// <summary>
            /// Contains a JSON representation of the result.
            /// </summary>
            public string result;

            /// <summary>
            /// An array containing the errors.
            /// </summary>
            public List<string> errors;
        }
    }
}
